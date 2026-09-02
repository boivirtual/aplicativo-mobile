import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sync_service.dart';
import '../services/animal_cache_service.dart';
import '../repositories/pesagem_repository.dart';
import '../widgets/indicador_conectividade_widget.dart';
import 'pesagem_itens_screen.dart';
import 'pesagem_consulta_screen.dart';
import 'pesagem_pendencias_revisao_screen.dart';
import 'package:boivirtual/utils/app_alert.dart';

class PesagemScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const PesagemScreen({super.key, this.onBack});

  @override
  State<PesagemScreen> createState() => _PesagemScreenState();
}

class _PesagemScreenState extends State<PesagemScreen> {
  String? fazendaSelecionada;
  String? motivoSelecionado;
  final TextEditingController _descricaoController = TextEditingController();
  final TextEditingController _qtdAPesarController = TextEditingController();

  final TextEditingController _criterioController = TextEditingController();
  List<String> _criteriosApartacao = [];

  List<dynamic> fazendasCarregadas = [];
  List<dynamic> pesagensPendentes = [];
  List<dynamic> pesagensFinalizadas = [];
  bool exibirFinalizadas = false;
  bool carregandoFinalizadas = false;
  bool _mostrarFormulario = false;
  bool _iniciando = false;
  String? _cnpjCarregado;

  final Color corDoRotulo = Colors.blueGrey[800]!;
  final Color corTextoPendente = const Color(0xFF455A64);

  StreamSubscription<int>? _subPendentesSync;
  int _pendentesSync = 0;
  bool _sincronizandoManualmente = false;

  StreamSubscription<int>? _subConflitos;
  int _pendenciasConflito = 0;

  bool carregandoPendentes = false;
  bool _baixandoAnimais = false;
  void _ouvirBaixandoAnimais() {
    if (mounted) setState(() => _baixandoAnimais = AnimalCacheService.instance.baixando.value);
  }

  bool _baixandoItensPendentes = false;
  void _ouvirBaixandoItensPendentes() {
    if (mounted) {
      setState(() => _baixandoItensPendentes =
          PesagemRepository.instance.baixandoItensPendentes.value);
    }
  }

  final Map<String, String> motivos = {
    '011': 'Controle Ganho de Peso',
    '002': 'Desmama',
    '016': 'MÃE de desmama',
    '003': 'Venda',
    '005': 'Tranferência',
    '012': 'Machos acima 8 meses',
    '013': 'Femeas 08 a 24 meses',
  };

  @override
  void initState() {
    super.initState();
    _carregarDadosIniciais();
    _subPendentesSync = SyncService.instance.pendentes.listen((qtd) {
      if (mounted) setState(() => _pendentesSync = qtd);
    });
    _subConflitos = SyncService.instance.conflitos.listen((qtd) {
      if (mounted) setState(() => _pendenciasConflito = qtd);
    });
    SyncService.instance.atualizarContagemPendentes();
    AnimalCacheService.instance.baixando.addListener(_ouvirBaixandoAnimais);
    PesagemRepository.instance.baixandoItensPendentes.addListener(
      _ouvirBaixandoItensPendentes,
    );
  }

  Future<void> _sincronizarAgora() async {
    setState(() => _sincronizandoManualmente = true);
    final resultado = await SyncService.instance.sincronizarAgora(
      ignorarRecuo: true,
    );
    if (!mounted) return;
    setState(() => _sincronizandoManualmente = false);

    if (resultado.processadas > 0) {
      _carregarDadosIniciais();
    }

    final mensagem = resultado.comErro > 0
        ? "${resultado.processadas} sincronizado(s), ${resultado.comErro} ainda pendente(s)."
        : resultado.processadas > 0
        ? "${resultado.processadas} sincronizado(s) com sucesso."
        : "Sem sinal ou nada novo para sincronizar.";

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  static const _corIndicador = Color(0xFF18385F);

  Widget _buildIndicadorCarregando() {
    final partes = <String>[
      if (carregandoPendentes) "pesagens pendentes",
      if (_baixandoItensPendentes) "itens das pesagens em aberto",
      if (_baixandoAnimais) "cadastro de animais das fazendas",
    ];
    final mensagem = "Baixando ${partes.join(', ')}...";
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.5),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: _corIndicador,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    mensagem,
                    style: const TextStyle(
                      color: _corIndicador,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIndicadorSync() {
    return Container(
      width: double.infinity,
      color: Colors.blueGrey[700],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _pendentesSync == 1
                  ? "1 pesagem pendente de sincronização"
                  : "$_pendentesSync pesagens pendentes de sincronização",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: _sincronizandoManualmente ? null : _sincronizarAgora,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
            ),
            child: _sincronizandoManualmente
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    "Sincronizar agora",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirPendenciasRevisao() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PesagemPendenciasRevisaoScreen(
          onBack: () => Navigator.pop(context),
        ),
      ),
    );
    SyncService.instance.atualizarContagemPendentes();
  }

  Widget _buildIndicadorPendenciasRevisao() {
    return Material(
      color: Colors.red[700],
      child: InkWell(
        onTap: _abrirPendenciasRevisao,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _pendenciasConflito == 1
                      ? "1 pendência recusada pelo servidor"
                      : "$_pendenciasConflito pendências recusadas pelo servidor",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Text(
                "Ver",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    _qtdAPesarController.dispose();
    _criterioController.dispose();
    _subPendentesSync?.cancel();
    _subConflitos?.cancel();
    AnimalCacheService.instance.baixando.removeListener(_ouvirBaixandoAnimais);
    PesagemRepository.instance.baixandoItensPendentes.removeListener(
      _ouvirBaixandoItensPendentes,
    );
    super.dispose();
  }

  String _formatarDataManual(String dataIso) {
    try {
      List<String> partes = dataIso.split(' ')[0].split('-');
      if (partes.length == 3) {
        return "${partes[2]}/${partes[1]}/${partes[0].substring(2)}";
      }
      return dataIso;
    } catch (e) {
      return dataIso;
    }
  }

  String _getNomeFazenda(String id) {
    final fazenda = fazendasCarregadas.firstWhere(
      (f) => f['id'].toString() == id,
      orElse: () => {'nome': '...'},
    );
    return fazenda['nome'].toString().toUpperCase();
  }

  Future<void> _carregarDadosIniciais() async {
    await _carregarFazendasEPendencias();
    await _carregarFinalizadas();
  }

  Future<void> _carregarFazendasEPendencias() async {
    final prefs = await SharedPreferences.getInstance();
    final String? fazendasJson = prefs.getString('userFazendas');
    final String? cnpj = prefs.getString('userCNPJ');
    _cnpjCarregado = cnpj;
    if (fazendasJson != null) {
      final List<dynamic> lista = json.decode(fazendasJson);
      setState(() {
        fazendasCarregadas = lista;
        if (fazendasCarregadas.length == 1) {
          fazendaSelecionada = fazendasCarregadas[0]['id'].toString();
        }
      });
      // Pré-carrega o cadastro completo de animais do cliente (não só as
      // fazendas do array do usuário) — "Consultar Mãe" precisa achar mãe
      // em qualquer fazenda, inclusive fêmeas inativas com filho ativo.
      AnimalCacheService.instance.garantirCacheCompleto(cnpj);
      setState(() => carregandoPendentes = true);
      try {
        final List<int> idsFazendas = lista
            .map((f) => int.parse(f['id'].toString()))
            .toList();
        final listaPendentes = await PesagemRepository.instance.listarPendentes(
          bd: cnpj,
          fazendas: idsFazendas,
        );
        setState(() {
          pesagensPendentes = listaPendentes;
        });
        // Baixa em segundo plano os itens de qualquer pesagem em aberto que
        // ainda não foi aberta neste aparelho — sem isso, se a internet cair
        // antes do vaqueiro abrir aquela pesagem específica no curral, ele
        // fica sem conseguir continuar de onde parou.
        PesagemRepository.instance.garantirItensDasPendentes(cnpj);
      } catch (e) {
        debugPrint("Erro pendências: $e");
      } finally {
        setState(() => carregandoPendentes = false);
      }
    }
  }

  Future<void> _carregarFinalizadas() async {
    final prefs = await SharedPreferences.getInstance();
    final String? fazendasJson = prefs.getString('userFazendas');
    final String? cnpj = prefs.getString('userCNPJ');
    if (fazendasJson != null && cnpj != null) {
      final List<dynamic> lista = json.decode(fazendasJson);
      final List<int> idsFazendas = lista
          .map((f) => int.parse(f['id'].toString()))
          .toList();
      setState(() => carregandoFinalizadas = true);
      try {
        final lista = await PesagemRepository.instance.listarFinalizadas(
          bd: cnpj,
          fazendas: idsFazendas,
        );
        setState(() {
          pesagensFinalizadas = lista;
        });
      } catch (e) {
        debugPrint("Erro finalizadas: $e");
      } finally {
        setState(() => carregandoFinalizadas = false);
      }
    }
  }

  void _adicionarCriterio(String texto) {
    if (texto.trim().isNotEmpty) {
      setState(() {
        _criteriosApartacao.add(texto.trim());
        _criterioController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(45.0),
        child: AppBar(
          backgroundColor: const Color(0xFF18385F),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: widget.onBack,
          ),
          title: const Text('Pesagem', style: TextStyle(fontSize: 18)),
          actions: const [
            IndicadorConectividadeWidget(),
            SizedBox(width: 4),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_pendenciasConflito > 0) _buildIndicadorPendenciasRevisao(),
              if (_pendentesSync > 0) _buildIndicadorSync(),
              Expanded(
                child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 10.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_mostrarFormulario)
                    Row(
                      children: [
                        const Icon(
                          Icons.scale,
                          color: Color(0xFF18385F),
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Nova Pesagem',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF18385F),
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          height: 32,
                          child: ElevatedButton(
                            onPressed: () =>
                                setState(() => _mostrarFormulario = false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4BBAEB),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Voltar',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() {
                          _mostrarFormulario = true;
                          exibirFinalizadas = false;
                        }),
                        icon: const Icon(
                          Icons.scale,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: const Text(
                          'Nova Pesagem',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF007AFF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),

                  if (_mostrarFormulario) ...[
                    const SizedBox(height: 15),
                    _buildFormularioNovaPesagem(),
                    const SizedBox(height: 30),
                  ],
                  if (!_mostrarFormulario) ...[const SizedBox(height: 25)],
                  _buildNavegacaoAbas(),
                  const SizedBox(height: 2),
                  if (!_mostrarFormulario) ...[
                    _buildTituloDinamico(),
                    const SizedBox(height: 5),
                    exibirFinalizadas
                        ? _buildListaFinalizadas()
                        : _buildListaPendentes(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
          if (carregandoPendentes || _baixandoAnimais || _baixandoItensPendentes)
            _buildIndicadorCarregando(),
        ],
      ),
    );
  }

  Widget _buildFormularioNovaPesagem() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDropdownMinimal(
            "Fazenda",
            fazendaSelecionada,
            fazendasCarregadas
                .map(
                  (f) => {
                    'id': f['id'].toString(),
                    'nome': f['nome'].toString(),
                  },
                )
                .toList(),
            (val) {
              setState(() => fazendaSelecionada = val);
              if (val != null) {
                AnimalCacheService.instance.garantirCacheDaFazenda(
                  val,
                  _cnpjCarregado,
                  nomeFazenda: _getNomeFazenda(val),
                );
              }
            },
            placeholder: "...",
          ),
          const SizedBox(height: 8),
          _buildDropdownMinimal(
            "Motivo",
            motivoSelecionado,
            motivos.entries.map((e) => {'id': e.key, 'nome': e.value}).toList(),
            (val) => setState(() => motivoSelecionado = val),
            placeholder: "...",
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 45,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF007AFF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _iniciando ? null : _validarEIniciarNovaPesagem,
                    child: _iniciando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "Iniciar Pesagem",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
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
                onPressed: () => _adicionarCriterio(_criterioController.text),
              ),
            ),
            onSubmitted: (val) => _adicionarCriterio(val),
          ),
        ),
        if (_criteriosApartacao.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Wrap(
              spacing: 6,
              runSpacing: -6,
              children: _criteriosApartacao
                  .map(
                    (tag) => Chip(
                      backgroundColor: Colors.blue[50],
                      label: Text(
                        tag,
                        style: TextStyle(fontSize: 11, color: Colors.blue[900]),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () =>
                          setState(() => _criteriosApartacao.remove(tag)),
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

  Future<int?> _criarPesagemSemItensNoServidor() async {
    final prefs = await SharedPreferences.getInstance();

    final String? cnpj = prefs.getString('userCNPJ');

    final String usuarioAtual =
        prefs.getString('userName')?.trim().isNotEmpty == true
        ? prefs.getString('userName')!.trim()
        : "App User";

    try {
      final bodyMap = {
        "bd": cnpj,
        "local_id": fazendaSelecionada,
        "epoca_id": motivoSelecionado,
        "lote": _descricaoController.text,
        "filtro_desc":
            "${_getNomeFazenda(fazendaSelecionada!)} ➔ ${motivos[motivoSelecionado]}",
        "qtd_a_pesar": _qtdAPesarController.text,
        "criterios_lista": _criteriosApartacao,

        // 👇 ESTE ERA O CAMPO QUE ESTAVA FALTANDO
        "usuario": usuarioAtual,
      };

      debugPrint("USUÁRIO ENVIADO CREATE PESAGEM: $usuarioAtual");
      debugPrint("JSON CREATE PESAGEM: ${json.encode(bodyMap)}");

      final resJson = await PesagemRepository.instance.criarPesagem(bodyMap);

      if (resJson['success'] == true) {
        return int.tryParse(resJson['pesagem_id'].toString());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Não foi possível iniciar a pesagem.")),
        );
      }
      return null;
    } catch (e) {
      debugPrint("Erro ao criar pesagem sem itens: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erro ao iniciar a pesagem.")),
        );
      }
      return null;
    }
  }

  void _validarEIniciarNovaPesagem() {
    if (fazendaSelecionada == null || fazendaSelecionada!.trim().isEmpty) {
      AppAlert.erro(context, 'Informe o campo Fazenda');
      return;
    }

    if (motivoSelecionado == null || motivoSelecionado!.trim().isEmpty) {
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

    _iniciarNovaPesagem();
  }

  void _iniciarNovaPesagem() async {
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _iniciando = true);

    final int? idPesagemCriada = await _criarPesagemSemItensNoServidor();
    if (!mounted) return;
    if (idPesagemCriada == null) {
      setState(() => _iniciando = false);
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PesagemItensScreen(
          fazendaSelecionada: fazendaSelecionada!,
          motivoSelecionado: motivoSelecionado!,
          descricaoLote: _descricaoController.text,
          qtdAPesar: _qtdAPesarController.text,
          criteriosApartacao: _criteriosApartacao,
          idPesagemExistente: idPesagemCriada,
          onBack: () => Navigator.pop(context),
        ),
      ),
    );

    if (!mounted) return;

    setState(() {
      if (fazendasCarregadas.length > 1) fazendaSelecionada = null;
      motivoSelecionado = null;
      _descricaoController.clear();
      _qtdAPesarController.clear();
      _criterioController.clear();
      _criteriosApartacao = [];
      _mostrarFormulario = false;
      _iniciando = false;
    });
    _carregarDadosIniciais();
  }

  Widget _buildNavegacaoAbas() {
    Color corTexto = _mostrarFormulario ? Colors.blue[300]! : Colors.grey[600]!;
    double tamanhoFonte = _mostrarFormulario ? 13.0 : 12.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (exibirFinalizadas || _mostrarFormulario) ...[
            GestureDetector(
              onTap: () => setState(() {
                exibirFinalizadas = false;
                _mostrarFormulario = false;
              }),
              child: Text(
                "Pesagens sem Finalizar",
                style: TextStyle(
                  fontSize: tamanhoFonte,
                  fontWeight: FontWeight.bold,
                  color: corTexto,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(width: 10),
          ],
          if (!exibirFinalizadas || _mostrarFormulario) ...[
            GestureDetector(
              onTap: () => setState(() {
                exibirFinalizadas = true;
                _mostrarFormulario = false;
              }),
              child: Text(
                "Pesagens Finalizadas",
                style: TextStyle(
                  fontSize: tamanhoFonte,
                  fontWeight: FontWeight.bold,
                  color: corTexto,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildTituloDinamico() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Center(
        child: Text(
          exibirFinalizadas ? "Pesagens Finalizadas" : "Pesagens sem finalizar",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.blue[300],
          ),
        ),
      ),
    );
  }

  Widget _buildListaPendentes() {
    if (pesagensPendentes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20.0),
        child: Text(
          "Nenhuma pesagem pendente",
          style: TextStyle(color: Colors.grey[400]),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pesagensPendentes.length,
      itemBuilder: (context, index) =>
          _buildItemLista(pesagensPendentes[index], finalizada: false),
    );
  }

  Widget _buildListaFinalizadas() {
    if (carregandoFinalizadas) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (pesagensFinalizadas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20.0),
        child: Text(
          "Nenhuma pesagem finalizada recentemente",
          style: TextStyle(color: Colors.grey[400]),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pesagensFinalizadas.length,
      itemBuilder: (context, index) =>
          _buildItemLista(pesagensFinalizadas[index], finalizada: true),
    );
  }

  Widget _buildItemLista(dynamic p, {required bool finalizada}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        visualDensity: VisualDensity.compact,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _formatarDataManual(p['tbl_pesagem_data'].toString()),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: corTextoPendente,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (p['fazenda_nome'] ??
                            _getNomeFazenda(
                              p['tbl_pesagem_codigo_local'].toString(),
                            ))
                        .toString(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: corTextoPendente,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              "Motivo: ${motivos[p['tbl_pesagem_codigo_epoca']?.toString()] ?? p['tbl_pesagem_codigo_epoca'] ?? '-'}",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: corTextoPendente,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              "Lote: ${p['tbl_pesagem_lote'] ?? 'Sem Lote'} | Pesados: ${p['tbl_pesagem_qtd_animais_pesados']}",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: corTextoPendente,
              ),
            ),
          ],
        ),
        trailing: finalizada
            ? IconButton(
                icon: const Icon(Icons.search, color: Colors.blue, size: 22),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PesagemConsultaScreen(
                        fazendaSelecionada: p['fazenda_nome'].toString(),
                        motivoSelecionado: p['tbl_pesagem_codigo_epoca']
                            .toString(),
                        descricaoLote: p['tbl_pesagem_lote'] ?? '',
                        qtdAPesar:
                            p['tbl_pesagem_qtd_animais_a_pesar']?.toString() ??
                            '0',
                        idPesagemExistente: int.parse(
                          p['tbl_pesagem_id'].toString(),
                        ),
                        onBack: () => Navigator.pop(context),
                      ),
                    ),
                  );
                },
              )
            : IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.scale, color: Colors.blue, size: 22),
                onPressed: () => _abrirPesagemExistente(p),
              ),
      ),
    );
  }

  void _abrirPesagemExistente(dynamic p) async {
    List<String> listaRecuperada = [];
    String? criteriosBanco = p['tbl_pesagem_criterios_apartacao']?.toString();
    if (criteriosBanco != null && criteriosBanco.trim().isNotEmpty) {
      listaRecuperada = criteriosBanco
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PesagemItensScreen(
          fazendaSelecionada: p['tbl_pesagem_codigo_local'].toString(),
          motivoSelecionado: p['tbl_pesagem_codigo_epoca'].toString(),
          descricaoLote: p['tbl_pesagem_lote'] ?? '',
          qtdAPesar: p['tbl_pesagem_qtd_animais_a_pesar']?.toString() ?? '0',
          criteriosApartacao: listaRecuperada,
          idPesagemExistente: int.parse(p['tbl_pesagem_id'].toString()),
          onBack: () => Navigator.pop(context),
        ),
      ),
    );
    _carregarDadosIniciais();
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
    Function(String?) onChanged, {
    String? placeholder,
  }) {
    return Container(
      height: 55,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: corDoRotulo, fontSize: 13),
            border: InputBorder.none,
          ),
          isExpanded: true,
          initialValue:
              value, // AQUI: Trocado 'value' por 'initialValue' conforme o erro sugeriu
          items: [
            // Item com value null pra representar "nada selecionado" de
            // verdade — sem isso, com value inicial null e nenhum item
            // correspondente, o Flutter destacava a PRIMEIRA opção da
            // lista (cinza, como se já estivesse selecionada), confundindo
            // o usuário e parecendo um título.
            if (placeholder != null)
              DropdownMenuItem<String>(
                value: null,
                child: Text(
                  placeholder,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                ),
              ),
            ...items.map(
              (item) => DropdownMenuItem(
                value: item['id'],
                child: Text(
                  item['nome']!,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
