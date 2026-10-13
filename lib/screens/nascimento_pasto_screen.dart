import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/daos/animal_cache_dao.dart';
import '../services/animal_cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/mapa_gado_sync_service.dart';
import '../widgets/indicador_conectividade_widget.dart';
import '../widgets/seletor_campo_widget.dart';

/// Tela "Mapa de Gado - Nascimento" (modal #modal_nascimento do web, em
/// form_mapa_gados_movimentacao.php). No aplicativo é uma tela própria,
/// porque o formulário é extenso demais para um modal.
///
/// Só abre com o aplicativo online (ver _abrirNascimento em
/// PastoMovimentacaoWidget).
///
/// Campos (controle de estoque por animal), os mesmos que o web mostra em
/// cada opção:
///   - Nascimento: Data Nascimento, Nº Animal, Nº Mãe, Pai Nº, Monta,
///     Sexo, Raça, Pelagem e Peso;
///   - Aborto, Absorção e Natimorto: Data Ocorrência, Nº Fêmea e Sexo.
///
/// Já funcionam: os selects (Pai Nº, Raça e Pelagem, vindos do servidor) e
/// a digitação do Nº Mãe / Nº Fêmea, com a lista de aproximação (mesmos
/// critérios do web, ver AnimalCacheDao.buscarFemeasParaNascimento) — a
/// fêmea só vale depois de escolhida na lista, como o Nº Animal da Morte.
/// As regras da estação de monta, as validações e a gravação são a próxima
/// etapa.
class NascimentoPastoScreen extends StatefulWidget {
  final String bd;
  final int fazendaId;
  final String fazendaCodigo;
  final String nomeFazenda;
  final int pastoId;
  final String nomePasto;
  final String? usuario;

  const NascimentoPastoScreen({
    super.key,
    required this.bd,
    required this.fazendaId,
    required this.fazendaCodigo,
    required this.nomeFazenda,
    required this.pastoId,
    required this.nomePasto,
    required this.usuario,
  });

  @override
  State<NascimentoPastoScreen> createState() => _NascimentoPastoScreenState();
}

/// Uma opção do "Pai Nº" (o web separa em dois grupos: SEMEM e ANIMAIS).
class _OpcaoPai {
  final String id;
  final String texto;
  final String grupo;
  const _OpcaoPai(this.id, this.texto, this.grupo);
}

class _NascimentoPastoScreenState extends State<NascimentoPastoScreen> {
  static const _azul = Color(0xFF18385F);
  static const _verde = Color(0xFF4CAF50);
  static const _azulVoltar = Color(0xFF4BBAEB);
  static final _corRotulo = Colors.blueGrey[800]!;

  /// Mesmos valores do web (radio opcao_nascimento): N = Nascimento,
  /// A = Aborto, B = Absorção, M = Natimorto.
  static const _opcoes = [
    MapEntry('N', 'Nascimento'),
    MapEntry('A', 'Aborto'),
    MapEntry('B', 'Absorção'),
    MapEntry('M', 'Natimorto'),
  ];

  final _maeController = TextEditingController();
  final _maeFoco = FocusNode();
  final _animalController = TextEditingController();
  final _pesoController = TextEditingController();

  String? _opcao;
  DateTime _data = _hoje();
  String? _sexo; // 'M' ou 'F'
  _OpcaoPai? _pai;
  String? _raca;
  String? _pelagem;

  // Selects (vêm do servidor ao abrir a tela).
  List<_OpcaoPai> _pais = [];
  List<MapEntry<String, String>> _racas = [];
  List<MapEntry<String, String>> _pelagens = [];
  bool _carregandoListas = true;
  bool _falhaListas = false;

  // Nº Mãe / Nº Fêmea
  bool _temCadastro = true;
  bool _atualizandoCadastro = false;
  List<Map<String, dynamic>> _sugestoes = [];
  Map<String, dynamic>? _mae; // linha de animais_cache escolhida na lista
  bool _maeInvalida = false;
  int _buscaAtual = 0;
  Timer? _esperaNaoEncontrado;
  OverlayEntry? _avisoNaoEncontrado;

  static DateTime _hoje() {
    final a = DateTime.now();
    return DateTime(a.year, a.month, a.day);
  }

  static String _formatar(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// "C-000000087" -> "C-87"; "000001874" -> "1874" (como a Pesagem mostra).
  static String _exibicao(String codigo) {
    if (codigo.contains('-')) {
      final partes = codigo.split('-');
      final numero = partes[1].replaceFirst(RegExp(r'^0+'), '');
      return '${partes[0]}-${numero.isEmpty ? '0' : numero}';
    }
    final numero = codigo.replaceFirst(RegExp(r'^0+'), '');
    return numero.isEmpty ? '0' : numero;
  }

  @override
  void initState() {
    super.initState();
    _carregarListas();
    _carregarCadastro();
  }

  @override
  void dispose() {
    _esperaNaoEncontrado?.cancel();
    _avisoNaoEncontrado?.remove();
    _maeController.dispose();
    _maeFoco.dispose();
    _animalController.dispose();
    _pesoController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Dados
  // ---------------------------------------------------------------------

  /// Pai Nº, Raça e Pelagem — mesmas listas do web.
  Future<void> _carregarListas() async {
    setState(() {
      _carregandoListas = true;
      _falhaListas = false;
    });
    final dados = await MapaGadoSyncService.instance.buscarListasNascimento(
      widget.bd,
    );
    if (!mounted) return;
    if (dados == null) {
      setState(() {
        _carregandoListas = false;
        _falhaListas = true;
      });
      return;
    }
    List<Map> lista(String chave) =>
        ((dados[chave] as List?) ?? const []).cast<Map>();
    String txt(Map m, String c) => (m[c] ?? '').toString().trim();

    final pais = <_OpcaoPai>[
      for (final s in lista('semens'))
        _OpcaoPai(
          txt(s, 'id'),
          '${txt(s, 'nome')} - ${txt(s, 'raca')}',
          'SEMEM',
        ),
      for (final a in lista('machos'))
        _OpcaoPai(
          txt(a, 'id'),
          '${_exibicao(txt(a, 'alfa').isEmpty ? txt(a, 'numerico') : '${txt(a, 'alfa')}-${txt(a, 'numerico')}')}'
              ' - ${txt(a, 'raca')}',
          'ANIMAIS',
        ),
    ];
    setState(() {
      _pais = pais;
      _racas = [
        for (final r in lista('racas'))
          MapEntry(txt(r, 'id'), txt(r, 'descricao')),
      ];
      _pelagens = [
        for (final p in lista('pelagens'))
          MapEntry(txt(p, 'id'), txt(p, 'descricao')),
      ];
      _carregandoListas = false;
    });
  }

  /// Como na Morte: busca o cadastro de animais do servidor ao abrir, para
  /// a lista do Nº Mãe refletir o que foi feito na web (animal baixado,
  /// reativado, cadastrado...). A busca já funciona com o que está no
  /// aparelho enquanto o download roda.
  Future<void> _carregarCadastro() async {
    final tem = await AnimalCacheDao.instance.temCacheParaFazenda(
      widget.fazendaCodigo,
    );
    if (!mounted) return;
    setState(() => _temCadastro = tem);
    if (!ConnectivityService.instance.temInternetReal) return;
    setState(() => _atualizandoCadastro = true);
    await AnimalCacheService.instance.garantirCacheCompleto(
      widget.bd,
      forcar: true,
    );
    if (!mounted) return;
    final temAgora = await AnimalCacheDao.instance.temCacheParaFazenda(
      widget.fazendaCodigo,
    );
    if (!mounted) return;
    setState(() {
      _atualizandoCadastro = false;
      _temCadastro = temAgora;
    });
    // Refaz a busca em andamento com o cadastro novo.
    if (_mae == null && _maeController.text.trim().isNotEmpty) {
      _aoDigitarMae(_maeController.text);
    }
  }

  // ---------------------------------------------------------------------
  // Nº Mãe / Nº Fêmea — lista de aproximação (igual ao Nº Animal da Morte)
  // ---------------------------------------------------------------------

  Future<void> _aoDigitarMae(String termo) async {
    final busca = ++_buscaAtual;
    _esperaNaoEncontrado?.cancel();
    // Mexeu no número: a fêmea precisa ser escolhida de novo.
    setState(() {
      _mae = null;
      _maeInvalida = false;
    });
    if (termo.trim().isEmpty) {
      setState(() => _sugestoes = []);
      return;
    }
    final lista = await AnimalCacheDao.instance.buscarFemeasParaNascimento(
      widget.fazendaCodigo,
      termo,
    );
    if (!mounted || busca != _buscaAtual) return;
    setState(() => _sugestoes = lista);
    if (lista.isEmpty) {
      _esperaNaoEncontrado = Timer(const Duration(milliseconds: 800), () {
        if (!mounted || busca != _buscaAtual) return;
        // Cadastro ainda baixando: a busca é refeita quando terminar.
        if (_atualizandoCadastro) return;
        _maeController.clear();
        _mostrarNaoEncontrado(
          'Cód ${termo.trim()} não encontrado ou está inativo!',
        );
      });
    }
  }

  void _escolherMae(Map<String, dynamic> animal) {
    _buscaAtual++;
    _esperaNaoEncontrado?.cancel();
    setState(() {
      _mae = animal;
      _maeInvalida = false;
      _sugestoes = [];
      _maeController.text = _exibicao(animal['codigo']?.toString() ?? '');
    });
    _maeFoco.unfocus();
  }

  /// No web, tocar no campo já preenchido limpa a fêmea para digitar outra.
  void _aoTocarMae() {
    if (_mae == null) return;
    setState(() {
      _mae = null;
      _maeController.clear();
      _sugestoes = [];
    });
  }

  /// "Nasc: 01/12/2019 - Nelore Branca"
  String get _descricaoMae {
    final a = _mae;
    if (a == null) return '';
    final nasc = DateTime.tryParse(a['nascimento']?.toString() ?? '');
    final raca = (a['raca'] ?? '').toString();
    final pelagem = (a['pelagem'] ?? '').toString();
    return 'Nasc: ${nasc == null ? '' : _formatar(nasc)} - $raca $pelagem'
        .trim();
  }

  /// Aviso vermelho no padrão da Pesagem/Morte: fica na tela até tocar em
  /// FECHAR e devolve o foco ao campo.
  void _mostrarNaoEncontrado(String mensagem) {
    _fecharNaoEncontrado(focar: false);
    FocusManager.instance.primaryFocus?.unfocus();
    _avisoNaoEncontrado = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).size.height * 0.35,
        left: 30,
        right: 30,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 25, 10, 10),
            decoration: BoxDecoration(
              color: Colors.red[900]!.withValues(alpha: 0.95),
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
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        mensagem,
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
                  child: TextButton(
                    onPressed: _fecharNaoEncontrado,
                    child: const Text(
                      'FECHAR',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
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
    Overlay.of(context, rootOverlay: true).insert(_avisoNaoEncontrado!);
  }

  void _fecharNaoEncontrado({bool focar = true}) {
    _avisoNaoEncontrado?.remove();
    _avisoNaoEncontrado = null;
    if (focar && mounted) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && _maeFoco.canRequestFocus) _maeFoco.requestFocus();
      });
    }
  }

  // ---------------------------------------------------------------------
  // Ações
  // ---------------------------------------------------------------------

  /// Como no web: trocar de opção limpa os campos.
  void _escolherOpcao(String valor) {
    if (_opcao == valor) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _buscaAtual++;
    _esperaNaoEncontrado?.cancel();
    setState(() {
      _opcao = valor;
      _data = _hoje();
      _sexo = null;
      _pai = null;
      _raca = null;
      _pelagem = null;
      _mae = null;
      _maeInvalida = false;
      _sugestoes = [];
      _maeController.clear();
      _animalController.clear();
      _pesoController.clear();
    });
  }

  Future<void> _escolherData() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: _hoje(),
      helpText: _opcao == 'N' ? 'Data do nascimento' : 'Data da ocorrência',
    );
    if (d != null) setState(() => _data = d);
  }

  /// "Pai Nº": são milhares de opções (todo sêmen e todo macho), então em
  /// vez do menu simples abre uma lista com busca, nos mesmos dois grupos
  /// do web (SEMEM e ANIMAIS).
  Future<void> _escolherPai() async {
    if (_pais.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final escolhido = await showDialog<_OpcaoPai>(
      context: context,
      builder: (_) => _ListaPaiDialog(
        opcoes: _pais,
        selecionado: _pai?.id,
        corRotulo: _corRotulo,
        corTitulo: _azul,
        corFechar: _azulVoltar,
      ),
    );
    if (escolhido == null || !mounted) return;
    // a primeira linha ("...") limpa o pai, como no web
    setState(() => _pai = escolhido.id.isEmpty ? null : escolhido);
  }

  /// A gravação é a próxima etapa.
  void _confirmar() => FocusManager.instance.primaryFocus?.unfocus();

  // ---------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Mapa de Gado - Nascimento',
          style: TextStyle(fontSize: 18, color: Colors.white),
        ),
        backgroundColor: _azul,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: const [IndicadorConectividadeWidget(), SizedBox(width: 8)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 16),
        children: [
          _cabecalho(),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
            child: _rotuloObrigatorio('Selecione uma opção', 14),
          ),
          Row(
            children: [
              for (final o in _opcoes)
                Expanded(
                  // mais espaço para o texto mais comprido
                  flex: o.value.length + 4,
                  child: _radio(
                    o.value,
                    marcado: _opcao == o.key,
                    aoTocar: () => _escolherOpcao(o.key),
                  ),
                ),
            ],
          ),
          if (_opcao != null) ...[
            const SizedBox(height: 6),
            // Painel cinza com as caixas brancas: mesmo padrão dos modais
            // de Morte e Nutrição.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._avisosDoTopo(),
                  if (_opcao == 'N')
                    ..._camposNascimento()
                  else
                    ..._camposOcorrencia(),
                  // no Nascimento o Confirmar fica na linha do Peso
                  if (_opcao != 'N') ...[
                    const SizedBox(height: 10),
                    _botao('Confirmar', _verde, _confirmar),
                  ],
                ],
              ),
            ),
          ] else
            Divider(color: Colors.grey[200], height: 16),
        ],
      ),
    );
  }

  List<Widget> _avisosDoTopo() => [
    if (_atualizandoCadastro) ...[
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Atualizando o cadastro de animais...',
            style: TextStyle(fontSize: 12, color: _corRotulo),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ],
    if (!_temCadastro && !_atualizandoCadastro) ...[
      _aviso(
        'O cadastro de animais desta fazenda ainda não foi baixado neste '
        'aparelho. Atualize os dados com internet.',
      ),
      const SizedBox(height: 8),
    ],
    if (_falhaListas && _opcao == 'N') ...[
      GestureDetector(
        onTap: _carregarListas,
        child: _aviso(
          'Não foi possível buscar as listas de Pai, Raça e Pelagem. '
          'Toque aqui para tentar de novo.',
        ),
      ),
      const SizedBox(height: 8),
    ],
  ];

  /// Lista de aproximação e descrição da fêmea, logo abaixo da linha do
  /// campo.
  List<Widget> _abaixoDaMae() => [
    if (_sugestoes.isNotEmpty) _listaSugestoes(),
    if (_mae != null) ...[
      const SizedBox(height: 6),
      Text(
        _descricaoMae,
        style: const TextStyle(
          fontSize: 13,
          color: Colors.blue,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  ];

  /// Opção Nascimento:
  ///   1. Data Nascimento
  ///   2. Nº Mãe e Pai Nº
  ///   3. Nº Animal e Monta
  ///   (Sexo)
  ///   4. Raça e Pelagem
  ///   5. Peso e Confirmar
  List<Widget> _camposNascimento() => [
    Row(
      children: [
        Expanded(child: _campoData('* Data Nascimento')),
        const SizedBox(width: 8),
        const Expanded(child: SizedBox()),
      ],
    ),
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(child: _campoMae('* Nº Mãe')),
        const SizedBox(width: 8),
        Expanded(child: _campoPai()),
      ],
    ),
    ..._abaixoDaMae(),
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(
          child: _campoTexto('Nº Animal', _animalController, numerico: true),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'Monta:',
              style: TextStyle(fontSize: 14, color: _corRotulo),
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 8),
    _campoSexo(),
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(
          child: _seletor(
            '* Raça',
            _raca,
            _racas,
            (v) => setState(() => _raca = v),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _seletor(
            'Pelagem',
            _pelagem,
            _pelagens,
            (v) => setState(() => _pelagem = v),
          ),
        ),
      ],
    ),
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(child: _campoTexto('* Peso', _pesoController, numerico: true)),
        const SizedBox(width: 8),
        Expanded(child: _botao('Confirmar', _verde, _confirmar, altura: 56)),
      ],
    ),
  ];

  /// Opções Aborto, Absorção e Natimorto (iguais no web).
  List<Widget> _camposOcorrencia() => [
    Row(
      children: [
        Expanded(child: _campoData('* Data Ocorrência')),
        const SizedBox(width: 8),
        Expanded(child: _campoMae('* Nº Fêmea')),
      ],
    ),
    ..._abaixoDaMae(),
    const SizedBox(height: 8),
    _campoSexo(),
  ];

  /// Tarja azul no mesmo padrão da tela do pasto, com a fazenda e o pasto
  /// na mesma linha (a fonte encolhe um pouco se o nome for comprido).
  Widget _cabecalho() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '${widget.nomeFazenda}  -  Pasto: ${widget.nomePasto}',
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.blue,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _rotuloObrigatorio(String texto, double fonte) => Text.rich(
    TextSpan(
      style: TextStyle(fontSize: fonte, color: _corRotulo),
      children: [
        const TextSpan(
          text: '* ',
          style: TextStyle(color: Colors.red),
        ),
        TextSpan(text: texto),
      ],
    ),
  );

  Widget _aviso(String texto) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF2DEDE),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      texto,
      style: const TextStyle(fontSize: 13, color: Color(0xFFA94442)),
    ),
  );

  Widget _radio(
    String texto, {
    required bool marcado,
    required VoidCallback aoTocar,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: aoTocar,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        // Sempre em uma linha: a fonte encolhe um pouco se não couber.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                marcado ? Icons.radio_button_checked : Icons.radio_button_off,
                color: marcado ? _azul : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(texto, style: TextStyle(fontSize: 14, color: _corRotulo)),
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Campos — mesmo padrão dos modais de Morte e Nutrição
  // -----------------------------------------------------------------------

  InputDecoration _decoracao(String rotulo) => InputDecoration(
    labelText: rotulo,
    labelStyle: TextStyle(fontSize: 14, color: _corRotulo),
    border: InputBorder.none,
    isDense: true,
    contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
  );

  Widget _caixa({required Widget child, bool erro = false}) => Container(
    height: 56,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: erro ? Border.all(color: Colors.red) : null,
    ),
    child: child,
  );

  Widget _campoTexto(
    String rotulo,
    TextEditingController controller, {
    bool numerico = false,
  }) => _caixa(
    child: TextField(
      controller: controller,
      keyboardType: numerico ? TextInputType.number : TextInputType.text,
      inputFormatters: numerico
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      textCapitalization: TextCapitalization.characters,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontSize: 15),
      decoration: _decoracao(rotulo),
    ),
  );

  Widget _campoMae(String rotulo) => _caixa(
    erro: _maeInvalida,
    child: TextField(
      controller: _maeController,
      focusNode: _maeFoco,
      enabled: _temCadastro,
      textCapitalization: TextCapitalization.characters,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontSize: 15),
      decoration: _decoracao(rotulo),
      onTap: _aoTocarMae,
      onChanged: _aoDigitarMae,
    ),
  );

  /// Lista de aproximação logo abaixo do campo (como na Morte e na
  /// Pesagem).
  Widget _listaSugestoes() => Container(
    margin: const EdgeInsets.only(top: 2),
    constraints: const BoxConstraints(maxHeight: 220),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
    ),
    child: ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _sugestoes.length,
      itemBuilder: (context, i) {
        final animal = _sugestoes[i];
        return ListTile(
          dense: true,
          title: Text(
            _exibicao(animal['codigo']?.toString() ?? ''),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          onTap: () => _escolherMae(animal),
        );
      },
    ),
  );

  Widget _campoData(String rotulo) => GestureDetector(
    onTap: _escolherData,
    child: _caixa(
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rotulo,
                    style: TextStyle(fontSize: 11, color: _corRotulo),
                  ),
                  const SizedBox(height: 2),
                  Text(_formatar(_data), style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
            Icon(Icons.calendar_month, color: _corRotulo, size: 20),
          ],
        ),
      ),
    ),
  );

  /// "* Sexo" com Macho e Fêmea, dentro de uma caixa como os outros campos.
  Widget _campoSexo() => _caixa(
    child: Padding(
      padding: const EdgeInsets.only(left: 12, right: 6),
      child: Row(
        children: [
          Text('* Sexo', style: TextStyle(fontSize: 14, color: _corRotulo)),
          const SizedBox(width: 14),
          Expanded(
            child: _radio(
              'Macho',
              marcado: _sexo == 'M',
              aoTocar: () => setState(() => _sexo = 'M'),
            ),
          ),
          Expanded(
            child: _radio(
              'Fêmea',
              marcado: _sexo == 'F',
              aoTocar: () => setState(() => _sexo = 'F'),
            ),
          ),
        ],
      ),
    ),
  );

  /// "Pai Nº" com a mesma cara do SeletorCampoWidget.
  Widget _campoPai() => GestureDetector(
    onTap: _escolherPai,
    child: Container(
      height: 56,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _pai == null
                ? Text(
                    'Pai Nº',
                    style: TextStyle(fontSize: 14, color: _corRotulo),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pai Nº',
                        style: TextStyle(fontSize: 11, color: _corRotulo),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _pai!.texto,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
          ),
          if (_carregandoListas)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Icon(Icons.arrow_drop_down, color: _corRotulo),
        ],
      ),
    ),
  );

  Widget _seletor(
    String rotulo,
    String? valor,
    List<MapEntry<String, String>> opcoes,
    ValueChanged<String> aoMudar,
  ) => IgnorePointer(
    // sem opções (listas ainda chegando) o toque não abre nada
    ignoring: opcoes.isEmpty,
    child: SeletorCampoWidget<String>(
      rotulo: rotulo,
      corRotulo: _corRotulo,
      valor: valor,
      opcoes: opcoes,
      onChanged: aoMudar,
    ),
  );

  Widget _botao(
    String texto,
    Color cor,
    VoidCallback aoTocar, {
    double altura = 45,
  }) => SizedBox(
    height: altura,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: cor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: aoTocar,
      child: Text(
        texto,
        style: const TextStyle(fontSize: 15, color: Colors.white),
      ),
    ),
  );
}

/// Lista do "Pai Nº" com busca, nos grupos SEMEM e ANIMAIS do web. A
/// primeira linha ("...") devolve uma opção de id vazio (sem pai).
class _ListaPaiDialog extends StatefulWidget {
  final List<_OpcaoPai> opcoes;
  final String? selecionado;
  final Color corRotulo;
  final Color corTitulo;
  final Color corFechar;

  const _ListaPaiDialog({
    required this.opcoes,
    required this.selecionado,
    required this.corRotulo,
    required this.corTitulo,
    required this.corFechar,
  });

  @override
  State<_ListaPaiDialog> createState() => _ListaPaiDialogState();
}

class _ListaPaiDialogState extends State<_ListaPaiDialog> {
  String _termo = '';

  /// Linhas da lista: String = título de grupo; _OpcaoPai = opção.
  List<Object> get _linhas {
    final t = _termo.trim().toUpperCase();
    final linhas = <Object>[];
    if (t.isEmpty) linhas.add(const _OpcaoPai('', '...', ''));
    String? grupo;
    for (final o in widget.opcoes) {
      if (t.isNotEmpty && !o.texto.toUpperCase().contains(t)) continue;
      if (o.grupo != grupo) {
        grupo = o.grupo;
        linhas.add(grupo);
      }
      linhas.add(o);
    }
    return linhas;
  }

  @override
  Widget build(BuildContext context) {
    final linhas = _linhas;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pai Nº',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: widget.corTitulo),
            ),
            const SizedBox(height: 10),
            Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                onChanged: (v) => setState(() => _termo = v),
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Buscar...',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                  prefixIcon: Icon(Icons.search, size: 20),
                  prefixIconConstraints: BoxConstraints(minWidth: 40),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: linhas.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum resultado.',
                          style: TextStyle(color: widget.corRotulo),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: linhas.length,
                        itemBuilder: (context, i) {
                          final linha = linhas[i];
                          if (linha is String) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                              child: Text(
                                linha,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: widget.corRotulo,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }
                          final o = linha as _OpcaoPai;
                          final marcado =
                              o.id.isNotEmpty && o.id == widget.selecionado;
                          return InkWell(
                            onTap: () => Navigator.pop(context, o),
                            child: Container(
                              color: marcado ? Colors.grey.shade200 : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 11,
                              ),
                              child: Text(
                                o.texto,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 45,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.corFechar,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Voltar',
                  style: TextStyle(fontSize: 15, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
