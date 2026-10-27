import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/daos/animal_cache_dao.dart';
import '../data/daos/mapa_gado_dao.dart';
import '../services/animal_cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/mapa_gado_sync_service.dart';
import '../utils/app_alert.dart';
import '../widgets/campo_topo_widget.dart';
import '../widgets/seletor_campo_widget.dart';

/// "Mapa de Gado - Morte" — botão Morte da tela do pasto, igual ao modal do
/// web (form_mapa_gados_movimentacao.php, controle de estoque POR ANIMAL):
/// Nº Animal (com a lista de aproximação, como na Pesagem), Motivo da
/// Morte, Data da morte e Observação.
///
/// Funciona offline: o animal vem do cadastro guardado no aparelho, a
/// morte é aplicada no cache na hora e entra na fila do mapa (mesma regra
/// de gravar_morte.php, repetida no servidor quando a fila é enviada).
///
/// Como no web, depois de gravar o modal continua aberto e limpo para
/// lançar outra morte; "Voltar" fecha.
class MorteAnimalModal extends StatefulWidget {
  final String bd;
  final int fazendaId;

  /// Id da fazenda como vem do login ("000000056") — é assim que o
  /// cadastro de animais do aparelho guarda a fazenda.
  final String fazendaCodigo;
  final String nomeFazenda;
  final int pastoId;
  final String nomePasto;
  final String? usuario;

  const MorteAnimalModal({
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
  State<MorteAnimalModal> createState() => _MorteAnimalModalState();
}

class _MorteAnimalModalState extends State<MorteAnimalModal> {
  static const _azulTitulo = Color(0xFF18385F);
  static const _verde = Color(0xFF4CAF50);
  static const _azulVoltar = Color(0xFF4BBAEB);
  static final Color _corRotulo = Colors.blueGrey.shade800;

  final _animalController = TextEditingController();
  final _animalFoco = FocusNode();
  final _obsController = TextEditingController();

  List<MapEntry<int, String>> _motivos = [];
  bool _temCadastro = true;

  /// Baixando o cadastro de animais do servidor (ao abrir, com internet).
  bool _atualizandoCadastro = false;

  List<Map<String, dynamic>> _sugestoes = [];
  Map<String, dynamic>? _animal; // linha de animais_cache já validada
  bool _emEstacaoMonta = false;
  bool _animalInvalido = false;

  int? _motivo;
  DateTime _dataMorte = _hoje();
  bool _gravando = false;
  int _buscaAtual = 0;

  // "Cód X não encontrado ou está inativo!" — mesmo aviso vermelho da Pesagem, depois de
  // 800 ms sem digitar (para não avisar com o número pela metade).
  Timer? _esperaNaoEncontrado;
  OverlayEntry? _avisoNaoEncontrado;

  static DateTime _hoje() {
    final a = DateTime.now();
    return DateTime(a.year, a.month, a.day);
  }

  @override
  void initState() {
    super.initState();
    _carregar();
    // morte enviada ao servidor (ou que falhou): relê a lista do dia
    MapaGadoSyncService.instance.versaoFila.addListener(_carregarRegistrosHoje);
  }

  @override
  void dispose() {
    MapaGadoSyncService.instance.versaoFila.removeListener(
      _carregarRegistrosHoje,
    );
    _esperaNaoEncontrado?.cancel();
    _avisoNaoEncontrado?.remove();
    _animalController.dispose();
    _animalFoco.dispose();
    _obsController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final motivos = await MapaGadoDao.instance.motivosMorte(widget.bd);
    final temCadastro = await AnimalCacheDao.instance.temCacheParaFazenda(
      widget.fazendaCodigo,
    );
    if (!mounted) return;
    setState(() {
      _motivos = motivos;
      _temCadastro = temCadastro;
    });
    _carregarRegistrosHoje();
    await _atualizarCadastro();
  }

  // ---------------------------------------------------------------------
  // Registros de Hoje: mortes lançadas hoje na fazenda (pela data de
  // inclusão no sistema; a data mostrada é a da morte). Vêm do servidor
  // (com internet) mais as que ainda estão na fila do aparelho (em
  // laranja, aguardando envio) — a Morte funciona offline.
  // ---------------------------------------------------------------------

  List<Map<String, dynamic>> _registrosServidor = [];
  List<Map<String, dynamic>> _registrosFila = [];

  Future<void> _carregarRegistrosHoje() async {
    final hoje = _iso(_hoje());
    final dao = MapaGadoDao.instance;
    final fila = await dao.mortesNaFila(widget.bd);
    final pastos = await dao.pastos(
      widget.bd,
      widget.fazendaId,
      incluirForaTabuleiro: true,
    );
    final nomePasto = {for (final p in pastos) p.id: p.descricao};
    final motivos = await dao.motivosMorte(widget.bd);
    final nomeMotivo = {for (final m in motivos) m.key: m.value};
    int numero(Object? v) => int.tryParse(v?.toString() ?? '') ?? 0;
    final daFila = [
      for (final p in fila)
        if (numero(p['fazenda']) == widget.fazendaId &&
            (p['data_hora'] ?? '').toString().startsWith(hoje))
          {
            'animal': _exibicao((p['codigo'] ?? '').toString()),
            'data': (p['data_morte'] ?? '').toString(),
            'sexo': (p['sexo'] ?? '').toString(),
            'motivo': nomeMotivo[numero(p['motivo'])] ?? '',
            'pasto': nomePasto[numero(p['pasto'])] ?? '',
            'pendente': true,
          },
    ];
    if (!mounted) return;
    setState(() => _registrosFila = daFila);

    final servidor = await MapaGadoSyncService.instance.buscarMortesDeHoje(
      bd: widget.bd,
      fazenda: widget.fazendaId,
    );
    if (!mounted || servidor == null) return;
    setState(() => _registrosServidor = servidor);
  }

  static const _colunasRegistros = [
    ('Nº Animal', 10),
    ('Data', 12),
    ('Sexo', 5),
    ('Motivo', 13),
  ];

  Widget _linhaRegistro(
    List<String> valores, {
    bool cabecalho = false,
    bool pendente = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      child: Row(
        children: [
          for (var i = 0; i < valores.length; i++)
            Expanded(
              flex: _colunasRegistros[i].$2,
              child: Text(
                valores[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: i == 2 ? TextAlign.center : TextAlign.left,
                style: TextStyle(
                  fontSize: cabecalho ? 11 : 12,
                  color: cabecalho
                      ? _corRotulo
                      : pendente
                      ? const Color(0xFFE65100)
                      : Colors.black87,
                  fontWeight: cabecalho ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Mesmo visual da lista "Registros de Hoje" do Nascimento.
  Widget _listaRegistrosHoje() {
    final registros = [..._registrosServidor, ..._registrosFila];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(
            'Registros de Hoje',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.blue[300],
            ),
          ),
        ),
        _linhaRegistro([
          for (final c in _colunasRegistros) c.$1,
        ], cabecalho: true),
        Divider(height: 1, color: Colors.grey.shade400),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: registros.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: Colors.grey.shade300),
            itemBuilder: (context, i) {
              final r = registros[i];
              final data = DateTime.tryParse((r['data'] ?? '').toString());
              return _linhaRegistro([
                (r['animal'] ?? '').toString(),
                data == null ? '' : _formatar(data),
                (r['sexo'] ?? '').toString(),
                (r['motivo'] ?? '').toString(),
              ], pendente: r['pendente'] == true);
            },
          ),
        ),
        if (_registrosFila.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Em laranja: aguardando envio ao servidor.',
              style: TextStyle(fontSize: 11, color: Color(0xFFE65100)),
            ),
          ),
      ],
    );
  }

  /// Com internet, busca o cadastro de animais do servidor toda vez que o
  /// modal abre — o cadastro do aparelho só era baixado uma vez por sessão,
  /// então um animal reativado (ou baixado) pela web com o aplicativo já
  /// aberto não aparecia (ou continuava aparecendo) aqui. A busca funciona
  /// com o que já está no aparelho enquanto o download roda.
  Future<void> _atualizarCadastro() async {
    if (!ConnectivityService.instance.temInternetReal) return;
    setState(() => _atualizandoCadastro = true);
    await AnimalCacheService.instance.garantirCacheCompleto(
      widget.bd,
      forcar: true,
    );
    if (!mounted) return;
    final temCadastro = await AnimalCacheDao.instance.temCacheParaFazenda(
      widget.fazendaCodigo,
    );
    if (!mounted) return;
    setState(() {
      _atualizandoCadastro = false;
      _temCadastro = temCadastro;
    });
    // Refaz a busca em andamento com o cadastro novo.
    if (_animal == null && _animalController.text.trim().isNotEmpty) {
      _aoDigitarAnimal(_animalController.text);
    }
  }

  // ---------------------------------------------------------------------
  // Nº Animal — lista de aproximação (igual à Pesagem)
  // ---------------------------------------------------------------------

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

  Future<void> _aoDigitarAnimal(String termo) async {
    final busca = ++_buscaAtual;
    _esperaNaoEncontrado?.cancel();
    // Mexeu no número: o animal precisa ser escolhido de novo.
    setState(() {
      _animal = null;
      _emEstacaoMonta = false;
      _animalInvalido = false;
    });
    if (termo.trim().isEmpty) {
      setState(() => _sugestoes = []);
      return;
    }
    final lista = await AnimalCacheDao.instance.buscarPorCodigo(
      widget.fazendaCodigo,
      termo,
    );
    final pendentes = await MapaGadoDao.instance.animaisComMortePendente(
      widget.bd,
    );
    if (!mounted || busca != _buscaAtual) return;
    setState(() {
      _sugestoes = lista
          .where(
            (a) => !pendentes.contains(
              int.tryParse(a['id_animal']?.toString() ?? '') ?? 0,
            ),
          )
          .take(6)
          .toList();
    });
    if (_sugestoes.isEmpty) {
      _esperaNaoEncontrado = Timer(const Duration(milliseconds: 800), () {
        if (!mounted || busca != _buscaAtual) return;
        // Cadastro ainda baixando: a busca é refeita quando terminar (o
        // animal pode estar justamente no que está chegando).
        if (_atualizandoCadastro) return;
        _animalController.clear();
        _mostrarNaoEncontrado(
          'Cód ${termo.trim()} não encontrado ou está inativo!',
        );
      });
    }
  }

  /// Aviso vermelho no padrão da Pesagem (pesagem_itens_screen.dart): fica
  /// na tela até tocar em FECHAR e devolve o foco ao Nº Animal.
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
        if (mounted && _animalFoco.canRequestFocus) _animalFoco.requestFocus();
      });
    }
  }

  Future<void> _escolherAnimal(Map<String, dynamic> animal) async {
    final id = int.tryParse(animal['id_animal']?.toString() ?? '') ?? 0;
    final emEstacao = await MapaGadoDao.instance.animalEmEstacaoMonta(
      widget.bd,
      id,
    );
    if (!mounted) return;
    _buscaAtual++;
    setState(() {
      _animal = animal;
      _emEstacaoMonta = emEstacao;
      _animalInvalido = false;
      _sugestoes = [];
      _animalController.text = _exibicao(animal['codigo']?.toString() ?? '');
    });
    _animalFoco.unfocus();
  }

  /// No web, tocar no campo já preenchido limpa o animal para digitar outro.
  void _aoTocarAnimal() {
    if (_animal == null) return;
    setState(() {
      _animal = null;
      _emEstacaoMonta = false;
      _animalController.clear();
      _sugestoes = [];
    });
  }

  static String _dataBr(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return iso ?? '';
    return _formatar(d);
  }

  static String _formatar(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// "Fêmea - Nasc: 01/12/2019 - Nelore Branca - Mãe: B-87" (igual ao web).
  String get _descricaoAnimal {
    final a = _animal;
    if (a == null) return '';
    final sexo = a['sexo'] == 'M' ? 'Macho' : 'Fêmea';
    final raca = (a['raca'] ?? '').toString();
    final pelagem = (a['pelagem'] ?? '').toString();
    var mae = (a['brinco_mae'] ?? '').toString();
    if (mae == 'Não inf.') mae = '';
    return '$sexo - Nasc: ${_dataBr(a['nascimento']?.toString())} - '
        '$raca $pelagem - Mãe: $mae';
  }

  // ---------------------------------------------------------------------
  // Gravação
  // ---------------------------------------------------------------------

  Future<void> _escolherData() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final hoje = _hoje();
    final d = await showDatePicker(
      context: context,
      initialDate: _dataMorte,
      firstDate: DateTime(2000),
      lastDate: hoje, // a data não pode ser maior que a data atual
      helpText: 'Data da morte',
    );
    if (d != null) setState(() => _dataMorte = d);
  }

  Future<void> _confirmar() async {
    if (_gravando) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final animal = _animal;

    if (animal == null) {
      setState(() {
        _animalInvalido = true;
        _animalController.clear();
        _sugestoes = [];
      });
      await AppAlert.erro(context, 'FALTA VALIDAR O CÓDIGO DO ANIMAL.');
      return;
    }
    final motivo = _motivo;
    if (motivo == null) {
      await AppAlert.erro(context, 'Informe o Motivo da Morte!');
      return;
    }
    if (_dataMorte.isAfter(_hoje())) {
      await AppAlert.erro(
        context,
        'A Data não pode ser maior que a data atual!',
      );
      return;
    }
    final nascimentoIso = (animal['nascimento'] ?? '').toString();
    final nascimento = DateTime.tryParse(nascimentoIso);
    if (nascimento != null &&
        _dataMorte.isBefore(
          DateTime(nascimento.year, nascimento.month, nascimento.day),
        )) {
      await AppAlert.erro(
        context,
        'A Data da Morte não pode ser menor que a Data do Nascimento.',
      );
      return;
    }

    final sexo = animal['sexo'] == 'M' ? 'M' : 'F';
    final nascimentoYmd = nascimento == null ? nascimentoIso : _iso(nascimento);

    setState(() => _gravando = true);
    try {
      // O pasto precisa ter um animal desse sexo/categoria para baixar.
      final erro = await MapaGadoDao.instance.validarMorte(
        bd: widget.bd,
        fazenda: widget.fazendaId,
        pasto: widget.pastoId,
        sexo: sexo,
        nascimento: nascimentoYmd,
      );
      if (!mounted) return;
      if (erro != null) {
        await AppAlert.erro(context, erro);
        return;
      }

      await MapaGadoSyncService.instance.registrarMorte(
        bd: widget.bd,
        fazenda: widget.fazendaId,
        pasto: widget.pastoId,
        animal: int.tryParse(animal['id_animal']?.toString() ?? '') ?? 0,
        codigo: (animal['codigo'] ?? '').toString(),
        sexo: sexo,
        nascimento: nascimentoYmd,
        motivo: motivo,
        dataMorte: _iso(_dataMorte),
        observacao: _obsController.text.trim(),
        usuario: widget.usuario,
      );
      if (!mounted) return;
      await AppAlert.sucesso(
        context,
        'Movimentação de morte processada com sucesso.',
      );
      if (!mounted) return;
      // Como no web: o modal reabre limpo para lançar outra morte.
      setState(() {
        _animal = null;
        _emEstacaoMonta = false;
        _animalInvalido = false;
        _animalController.clear();
        _obsController.clear();
        _sugestoes = [];
        _motivo = null;
        _dataMorte = _hoje();
      });
      _carregarRegistrosHoje();
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  // ---------------------------------------------------------------------
  // Layout — padrão do modal "Editar Pesagem" / Composição do Lote
  // ---------------------------------------------------------------------

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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Morte',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: _azulTitulo),
              ),
              const SizedBox(height: 10),
              _tarja(),
              const SizedBox(height: 10),
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
                  'O cadastro de animais desta fazenda ainda não foi baixado '
                  'neste aparelho. Atualize os dados com internet.',
                ),
                const SizedBox(height: 8),
              ],
              _campoAnimal(),
              if (_sugestoes.isNotEmpty) _listaSugestoes(),
              if (_animal != null) ...[
                const SizedBox(height: 6),
                Text(
                  _descricaoAnimal,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (_emEstacaoMonta) ...[
                const SizedBox(height: 6),
                _aviso('Animal em Estação de Monta.'),
              ],
              const SizedBox(height: 8),
              SeletorCampoWidget<int>(
                rotulo: '* Motivo da Morte',
                corRotulo: _corRotulo,
                destaque: true,
                valor: _motivo,
                opcoes: _motivos,
                onChanged: (v) => setState(() => _motivo = v),
              ),
              const SizedBox(height: 8),
              _campoData(),
              const SizedBox(height: 8),
              _campoObservacao(),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _botao('Confirmar', _verde, _confirmar)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _botao(
                      'Voltar',
                      _azulVoltar,
                      () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
              if (_registrosServidor.isNotEmpty ||
                  _registrosFila.isNotEmpty) ...[
                const SizedBox(height: 14),
                _listaRegistrosHoje(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Fazenda e pasto na mesma linha (a fonte encolhe um pouco se o nome for
  /// comprido).
  Widget _tarja() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.blue.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '${widget.nomeFazenda}  -  ${widget.nomePasto}',
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

  Widget _campoAnimal() => CampoTextoTopo(
    rotulo: '* Nº Animal',
    corRotulo: _corRotulo,
    controller: _animalController,
    focusNode: _animalFoco,
    enabled: _temCadastro,
    erro: _animalInvalido,
    // teclado numérico: o animal é procurado pelo número
    keyboardType: TextInputType.number,
    textCapitalization: TextCapitalization.characters,
    onTap: _aoTocarAnimal,
    onChanged: _aoDigitarAnimal,
  );

  /// Lista de aproximação logo abaixo do Nº Animal (como na Pesagem).
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
          onTap: () => _escolherAnimal(animal),
        );
      },
    ),
  );

  Widget _campoData() => CampoValorTopo(
    rotulo: '* Data da morte',
    corRotulo: _corRotulo,
    valor: _formatar(_dataMorte),
    icone: Icon(Icons.calendar_month, color: _corRotulo, size: 20),
    onTap: _escolherData,
  );

  Widget _campoObservacao() => CampoTextoTopo(
    rotulo: 'Observação',
    corRotulo: _corRotulo,
    controller: _obsController,
    altura: null,
    linhas: 2,
    textCapitalization: TextCapitalization.characters,
    inputFormatters: [_Maiusculas()],
  );

  Widget _botao(String texto, Color cor, VoidCallback aoTocar) => SizedBox(
    height: 45,
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

/// Observação sempre em maiúsculas (onkeyup='maiuscula(this)' no web).
class _Maiusculas extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue antigo,
    TextEditingValue novo,
  ) => novo.copyWith(text: novo.text.toUpperCase());
}
