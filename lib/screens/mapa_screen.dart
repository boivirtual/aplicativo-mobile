import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/daos/mapa_gado_dao.dart';
import '../services/mapa_gado_sync_service.dart';
import '../utils/mapa_tabuleiro_calculo.dart';
import '../widgets/cabecalho_fazenda_widget.dart';
import '../widgets/indicador_conectividade_widget.dart';
import 'composicao_descricao_lote_screen.dart';

/// Mapa de Gado — visão Tabuleiro, igual à primeira tela do sistema web
/// (form_mapa_gados.php + ler_mapa_gados.php): um card por pasto, pastos
/// de ENTRADA/SAÍDA primeiro (em branco), depois os demais coloridos por
/// módulo, com bezerros/fêmeas/machos, total do pasto, tipo de capim,
/// total de animais da fazenda e busca por nome do pasto.
///
/// Mover TODOS os animais de um pasto para outro, igual ao web: segurar e
/// arrastar o card (no web, arrastar com o mouse) ou "Mover por toque"
/// (toca na origem, depois no destino). Se o pasto destino já tinha
/// descrição do lote, abre a "Composição da Descrição do Lote" (manter ou
/// criar nova).
///
/// Offline-first: a tela sempre lê do cache local (ver MapaGadoDao) e as
/// contagens são calculadas na hora (MapaTabuleiroCalculo). Mover animais
/// aplica no cache na hora e entra numa fila que sobe sozinha quando houver
/// internet (MapaGadoSyncService). O cache é atualizado na abertura do app
/// (AtualizandoDadosScreen), ao abrir esta tela e no "puxar pra atualizar".
class MapaScreen extends StatefulWidget {
  final VoidCallback onBack;
  const MapaScreen({super.key, required this.onBack});

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  static const _azul = Color(0xFF18385F);

  String? fazendaSelecionada;
  List<dynamic> fazendasCarregadas = [];
  bool carregando = true;

  String? _bd;
  String? _usuario;
  List<PastoTabuleiro> _cards = [];
  DateTime? _atualizadoEm;
  bool _lendoCache = false;
  bool _baixando = false;

  int _pendentes = 0;
  List<String> _erros = [];

  final _buscaController = TextEditingController();
  String _termoBusca = '';

  // Mover por toque (alternativa ao arrastar, igual ao web).
  bool _modoToque = false;
  int? _origemToque;

  // Arrastar.
  int? _pastoSobArraste;
  final _scrollController = ScrollController();
  final _gridKey = GlobalKey();
  Timer? _autoScroll;
  bool _arrastando = false;
  double _velocidadeAutoScroll = 0;

  @override
  void initState() {
    super.initState();
    MapaGadoSyncService.instance.versaoFila.addListener(_aoMudarFila);
    _carregarContexto();
  }

  @override
  void dispose() {
    MapaGadoSyncService.instance.versaoFila.removeListener(_aoMudarFila);
    _buscaController.dispose();
    _scrollController.dispose();
    _autoScroll?.cancel();
    super.dispose();
  }

  void _aoMudarFila() => _atualizarFila();

  Future<void> _carregarContexto() async {
    final prefs = await SharedPreferences.getInstance();
    final fazendasJson = prefs.getString('userFazendas');
    setState(() {
      _bd = prefs.getString('userCNPJ');
      _usuario = prefs.getString('userName');
      if (fazendasJson != null) {
        fazendasCarregadas = json.decode(fazendasJson);
        // Uma fazenda só: já vem selecionada e o tabuleiro carrega direto.
        if (fazendasCarregadas.length == 1) {
          fazendaSelecionada = fazendasCarregadas[0]['id'].toString();
        }
      }
      carregando = false;
    });
    await _lerDoCache();
    await _atualizarFila();
    await _baixarEAtualizar();
  }

  List<int> get _idsFazendas => fazendasCarregadas
      .map((f) => int.tryParse((f as Map)['id'].toString()) ?? 0)
      .where((id) => id > 0)
      .toList();

  /// O id da fazenda no login vem com zeros à esquerda ("000000056"); no
  /// cache fica o inteiro (56).
  int? get _fazendaId =>
      fazendaSelecionada == null ? null : int.tryParse(fazendaSelecionada!);

  void _selecionarFazenda(String? id) {
    setState(() {
      fazendaSelecionada = id;
      _cards = [];
      _atualizadoEm = null;
      _origemToque = null;
    });
    _lerDoCache();
  }

  /// Envia pendências, baixa o tabuleiro do servidor (melhor esforço —
  /// offline ou erro mantém o cache) e relê. Ao abrir a tela e no "puxar
  /// pra atualizar".
  Future<void> _baixarEAtualizar() async {
    if (_bd == null || _idsFazendas.isEmpty) return;
    setState(() => _baixando = true);
    final ok = await MapaGadoSyncService.instance.baixar(_bd, _idsFazendas);
    if (!mounted) return;
    setState(() => _baixando = false);
    if (ok) await _lerDoCache();
    await _atualizarFila();
  }

  Future<void> _atualizarFila() async {
    if (_bd == null) return;
    final pendentes = await MapaGadoDao.instance.contar(_bd!, 'pendente');
    final erros = await MapaGadoDao.instance.mensagensDeErro(_bd!);
    if (!mounted) return;
    setState(() {
      _pendentes = pendentes;
      _erros = erros;
    });
  }

  Future<void> _lerDoCache() async {
    final fazendaId = _fazendaId;
    if (_bd == null || fazendaId == null) return;
    setState(() => _lendoCache = true);

    final dao = MapaGadoDao.instance;
    final categorias = await dao.categorias(_bd!);
    final pastos = await dao.pastos(_bd!, fazendaId);
    final animais = await dao.animais(_bd!, fazendaId);
    final atualizadoEm = await dao.atualizadoEm(_bd!, fazendaId);

    final cards = MapaTabuleiroCalculo.calcular(
      pastos: pastos,
      animais: animais,
      categorias: categorias,
    );

    if (!mounted || _fazendaId != fazendaId) return;
    setState(() {
      _cards = cards;
      _atualizadoEm = atualizadoEm;
      _lendoCache = false;
    });
  }

  // ---------------------------------------------------------------------
  // Mover todos os animais
  // ---------------------------------------------------------------------

  void _alternarModoToque() {
    setState(() {
      _modoToque = !_modoToque;
      _origemToque = null;
    });
  }

  /// Toque no card: no modo toque escolhe origem/destino; fora dele, abrir
  /// as funcionalidades do pasto fica para a próxima etapa.
  void _tocarCard(PastoTabuleiro card) {
    if (!_modoToque) return;

    if (_origemToque == null) {
      // Pasto vazio não pode ser origem, igual ao arrastar.
      if (card.total == 0) return;
      setState(() => _origemToque = card.pasto.id);
      return;
    }
    if (_origemToque == card.pasto.id) {
      // Tocar de novo na origem cancela a seleção.
      setState(() => _origemToque = null);
      return;
    }

    final origem = _cards.firstWhere((c) => c.pasto.id == _origemToque);
    setState(() => _origemToque = null);
    _moverTudo(origem, card);
  }

  Future<void> _moverTudo(PastoTabuleiro origem, PastoTabuleiro destino) async {
    if (_bd == null || origem.pasto.id == destino.pasto.id) return;

    final confirmou = await perguntarSimNao(
      context,
      titulo: 'Mapa de Gado - Mensagem',
      mensagem:
          'Mover TODOS os animais do pasto ${origem.pasto.descricao} para o pasto ${destino.pasto.descricao}?',
    );
    if (!confirmou || !mounted) return;

    // Como no web: decide pela descrição do lote do destino ANTES de mover.
    final descricaoDestinoAntes = destino.pasto.descricaoLote;

    await MapaGadoSyncService.instance.transferirTudo(
      bd: _bd!,
      origem: origem.pasto.id,
      destino: destino.pasto.id,
      usuario: _usuario,
    );
    await _lerDoCache();
    if (!mounted) return;

    // Destino sem descrição: não precisa fazer mais nada (se a origem
    // tinha, ela já foi junto — Premissa 1).
    if (descricaoDestinoAntes.isEmpty) return;

    final descricoes = await MapaGadoDao.instance.descricoesLote(_bd!);
    if (!mounted) return;
    final resultado = await Navigator.of(context).push<NovaDescricaoLote>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ComposicaoDescricaoLoteScreen(
          nomePasto: destino.pasto.descricao,
          descricaoAtual: descricaoDestinoAntes,
          descricoes: descricoes,
        ),
      ),
    );
    // Ao voltar da composição, não devolver o foco para a busca.
    FocusManager.instance.primaryFocus?.unfocus();
    if (resultado == null || !mounted) return; // Manter

    await MapaGadoSyncService.instance.gravarDescricaoLote(
      bd: _bd!,
      pasto: destino.pasto.id,
      descricaoLote: resultado.descricao,
      lotes: resultado.lotes,
      usuario: _usuario,
    );
    await _lerDoCache();
  }

  // Rolagem automática enquanto arrasta perto do topo/rodapé do tabuleiro.
  //
  // A posição do dedo vem do Listener da tela (onPointerMove), e não do
  // onDragUpdate do card: quando a lista rola, o card que está sendo
  // arrastado sai da tela e é descartado pela GridView, e a partir daí o
  // Flutter não chama mais o onDragUpdate dele — a rolagem ficava presa na
  // direção em que começou, sem conseguir voltar.
  void _aoMoverDedo(Offset posicaoGlobal) {
    if (!_arrastando) return;
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(posicaoGlobal);
    const margem = 80.0;
    double v = 0;
    if (local.dy < margem) {
      v = -((margem - local.dy) / margem) * 18;
    } else if (local.dy > box.size.height - margem) {
      v = ((local.dy - (box.size.height - margem)) / margem) * 18;
    }
    _velocidadeAutoScroll = v.clamp(-24.0, 24.0);
    if (v == 0) {
      _autoScroll?.cancel();
      _autoScroll = null;
    } else {
      _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (t) {
        if (!_arrastando || !_scrollController.hasClients) {
          t.cancel();
          _autoScroll = null;
          return;
        }
        final pos = _scrollController.position;
        final alvo = (pos.pixels + _velocidadeAutoScroll)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent);
        _scrollController.jumpTo(alvo);
      });
    }
  }

  /// Fim do arraste. Também é chamado quando o dedo sai da tela (ver o
  /// Listener em build): o card que está sendo arrastado pode rolar para
  /// fora da tela e ser descartado pela GridView — aí o Flutter não chama
  /// mais o onDragEnd dele, e a rolagem automática ficava ligada para
  /// sempre (empurrando a lista e impedindo rolar no sentido contrário).
  void _fimArraste() {
    _arrastando = false;
    _autoScroll?.cancel();
    _autoScroll = null;
    _velocidadeAutoScroll = 0;
    if (mounted && _pastoSobArraste != null) {
      setState(() => _pastoSobArraste = null);
    }
  }

  // ---------------------------------------------------------------------
  // Tela
  // ---------------------------------------------------------------------

  int get _totalFazenda => _cards.fold(0, (soma, c) => soma + c.total);

  List<PastoTabuleiro> get _cardsFiltrados {
    if (_termoBusca.isEmpty) return _cards;
    final termo = _termoBusca.toUpperCase();
    return _cards
        .where((c) => c.pasto.descricao.toUpperCase().contains(termo))
        .toList();
  }

  /// Mesmas quebras do web: col-xs-3 (4 por linha), 3 por linha até 459px,
  /// 2 por linha até 375px; telas maiores (tablet) seguem col-md-2/col-lg-1.
  int _colunasPorLargura(double largura) {
    if (largura <= 375) return 2;
    if (largura <= 459) return 3;
    if (largura < 992) return 4;
    if (largura < 1200) return 6;
    return 12;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Mapa de Gado',
          style: TextStyle(fontSize: 18, color: Colors.white),
        ),
        backgroundColor: _azul,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack, // Volta para a Home
        ),
        actions: const [IndicadorConectividadeWidget(), SizedBox(width: 8)],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Antes de escolher: o select. Depois: tarja azul com a
                // fazenda e o total (mesmo visual da tarja da Pesagem) e o
                // ícone de edição para trocar de fazenda.
                if (fazendaSelecionada == null)
                  CabecalhoFazendaWidget(
                    fazendaSelecionada: fazendaSelecionada,
                    fazendasCarregadas: fazendasCarregadas,
                    onChanged: _selecionarFazenda,
                    mostrarIcone: false,
                    textoVazio: '...',
                  )
                else
                  _buildTarjaFazenda(),
                if (_baixando)
                  const LinearProgressIndicator(
                    minHeight: 2,
                    color: _azul,
                    backgroundColor: Color(0xFFF1F3F6),
                  ),
                // Acompanha o dedo durante o arraste (ver _aoMoverDedo) e
                // dedo saiu da tela = arraste terminou (ver _fimArraste).
                Expanded(
                  child: Listener(
                    onPointerMove: (e) => _aoMoverDedo(e.position),
                    onPointerUp: (_) {
                      if (_arrastando) _fimArraste();
                    },
                    onPointerCancel: (_) {
                      if (_arrastando) _fimArraste();
                    },
                    child: _buildConteudo(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildConteudo() {
    if (fazendaSelecionada == null) {
      return Center(
        child: Text(
          "Selecione uma fazenda para visualizar o mapa.",
          style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
        ),
      );
    }

    if (_cards.isEmpty) {
      if (_lendoCache || _baixando) {
        return const Center(child: CircularProgressIndicator());
      }
      return RefreshIndicator(
        onRefresh: _baixarEAtualizar,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                _atualizadoEm == null
                    ? "O mapa desta fazenda ainda não foi baixado neste aparelho.\nConecte-se à internet e puxe a tela para baixo para atualizar."
                    : "Nenhum pasto cadastrado para esta fazenda.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      );
    }

    final filtrados = _cardsFiltrados;

    return Column(
      children: [
        _buildBarraTotalEBusca(),
        if (_modoToque) _buildAvisoModoToque(),
        if (_erros.isNotEmpty) _buildAvisoErros(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _baixarEAtualizar,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final colunas = _colunasPorLargura(constraints.maxWidth);
                final largura =
                    (constraints.maxWidth - 16 - (colunas - 1) * 6) / colunas;
                return GridView.builder(
                  key: _gridKey,
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: colunas,
                    mainAxisExtent: 120,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: filtrados.length,
                  itemBuilder: (context, i) =>
                      _buildCardInterativo(filtrados[i], largura),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCardInterativo(PastoTabuleiro card, double largura) {
    final destaque = _pastoSobArraste == card.pasto.id
        ? _Destaque.destino
        : _origemToque == card.pasto.id
        ? _Destaque.origem
        : _Destaque.nenhum;

    Widget conteudo = _CardPasto(
      card: card,
      destaque: destaque,
      onTap: () => _tocarCard(card),
    );

    // Pasto vazio não pode ser arrastado (igual ao web); no modo toque o
    // arrastar fica desligado.
    if (card.total > 0 && !_modoToque) {
      conteudo = LongPressDraggable<PastoTabuleiro>(
        data: card,
        hapticFeedbackOnStart: true,
        onDragStarted: () => _arrastando = true,
        onDragEnd: (_) => _fimArraste(),
        onDraggableCanceled: (_, _) => _fimArraste(),
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.85,
            child: SizedBox(
              width: largura,
              height: 120,
              child: _CardPasto(card: card, destaque: _Destaque.origem),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: conteudo),
        child: conteudo,
      );
    }

    return DragTarget<PastoTabuleiro>(
      onWillAcceptWithDetails: (d) {
        final aceita = d.data.pasto.id != card.pasto.id;
        if (aceita && _pastoSobArraste != card.pasto.id) {
          setState(() => _pastoSobArraste = card.pasto.id);
        }
        return aceita;
      },
      onLeave: (_) {
        if (_pastoSobArraste == card.pasto.id) {
          setState(() => _pastoSobArraste = null);
        }
      },
      onAcceptWithDetails: (d) {
        _fimArraste();
        _moverTudo(d.data, card);
      },
      builder: (context, _, _) => conteudo,
    );
  }

  String get _nomeFazendaSelecionada {
    final f = fazendasCarregadas.firstWhere(
      (f) => (f as Map)['id'].toString() == fazendaSelecionada,
      orElse: () => {'nome': ''},
    );
    return (f as Map)['nome'].toString().toUpperCase();
  }

  Widget _buildTarjaFazenda() {
    final temOutras = fazendasCarregadas.length > 1;
    return Container(
      width: double.infinity,
      color: const Color(0xFFF1F3F6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Container(
        padding: EdgeInsets.fromLTRB(10, 8, temOutras ? 0 : 10, 8),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                  children: [
                    TextSpan(text: _nomeFazendaSelecionada),
                    if (_cards.isNotEmpty) ...[
                      const TextSpan(text: '  ➔  '),
                      TextSpan(
                        text: '$_totalFazenda Animais',
                        // A fonte do app (FuturaStd) só tem a versão Light,
                        // então fontWeight quase não muda nada: o traço é
                        // engrossado com "sombras" da mesma cor coladas no
                        // texto.
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          shadows: [
                            Shadow(color: Colors.blue, offset: Offset(0.5, 0)),
                            Shadow(color: Colors.blue, offset: Offset(-0.5, 0)),
                            Shadow(color: Colors.blue, offset: Offset(0, 0.5)),
                            Shadow(color: Colors.blue, offset: Offset(0, -0.5)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Uma fazenda só: não há outra para escolher.
            if (temOutras)
              IconButton(
                onPressed: _escolherOutraFazenda,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_note, color: Colors.blue, size: 22),
                tooltip: 'Trocar de fazenda',
              ),
          ],
        ),
      ),
    );
  }

  /// Modal para escolher outra fazenda; ao escolher, recarrega o tabuleiro.
  Future<void> _escolherOutraFazenda() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final escolhida = await showDialog<String>(
      context: context,
      requestFocus: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Selecione a Fazenda',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final f in fazendasCarregadas)
                ListTile(
                  dense: true,
                  selected: (f as Map)['id'].toString() == fazendaSelecionada,
                  selectedTileColor: Colors.grey.shade200,
                  title: Text(
                    f['nome'].toString().toUpperCase(),
                    style: const TextStyle(fontSize: 14, color: Color(0xFF455A64)),
                  ),
                  onTap: () => Navigator.pop(ctx, f['id'].toString()),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (escolhida != null && escolhida != fazendaSelecionada) {
      _buscaController.clear();
      _termoBusca = '';
      _selecionarFazenda(escolhida);
    }
  }

  Widget _buildBarraTotalEBusca() {
    return Container(
      color: const Color(0xFFF1F3F6),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Troca para o Mapa Satélite (igual ao web) — o clique fica
              // para a etapa do mapa satélite.
              IconButton(
                tooltip: 'Mapa Satélite',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.map_outlined, color: Colors.grey, size: 24),
                onPressed: () {},
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _buscaController,
                    onChanged: (v) => setState(() => _termoBusca = v.trim()),
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Buscar pasto...',
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36),
                      suffixIcon: _termoBusca.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.cancel, size: 18),
                              onPressed: () {
                                _buscaController.clear();
                                setState(() => _termoBusca = '');
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _modoToque ? const Color(0xFF2E7D32) : Colors.white,
                    foregroundColor: _modoToque ? Colors.white : const Color(0xFF455A64),
                    side: BorderSide(
                      color: _modoToque ? const Color(0xFF2E7D32) : const Color(0xFFCFD8DC),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: _alternarModoToque,
                  icon: Icon(_modoToque ? Icons.open_with : Icons.touch_app, size: 16),
                  label: Text(
                    _modoToque ? 'Voltar para arrastar' : 'Mover por toque',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          if (_pendentes > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _pendentes == 1
                    ? '1 movimentação aguardando envio'
                    : '$_pendentes movimentações aguardando envio',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFE65100),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvisoModoToque() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD9EDF7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 13, color: Color(0xFF31708F)),
          children: [
            TextSpan(text: 'Modo toque ativado: toque no pasto de '),
            TextSpan(text: 'origem', style: TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: ' (fica com borda laranja), depois toque no pasto de '),
            TextSpan(text: 'destino', style: TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }

  Widget _buildAvisoErros() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF2DEDE),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_erros.length == 1 ? 'Uma movimentação não foi aceita' : '${_erros.length} movimentações não foram aceitas'} pelo servidor: ${_erros.last}',
              style: const TextStyle(fontSize: 13, color: Color(0xFFA94442)),
            ),
          ),
          IconButton(
            tooltip: 'Fechar',
            icon: const Icon(Icons.close, size: 18, color: Color(0xFFA94442)),
            onPressed: () async {
              await MapaGadoDao.instance.limparErros(_bd!);
              await _baixarEAtualizar();
            },
          ),
        ],
      ),
    );
  }
}

enum _Destaque { nenhum, origem, destino }

/// Card de um pasto — mesma composição do web: nome no topo, à esquerda
/// os ícones de bezerro/vaca/boi com as quantidades (só os que têm
/// animal), linha vertical, total do pasto à direita e o tipo de capim no
/// canto inferior direito. Borda azul = destino do arraste; laranja
/// tracejada no web (aqui contínua) = origem escolhida no modo toque.
class _CardPasto extends StatelessWidget {
  final PastoTabuleiro card;
  final _Destaque destaque;
  final VoidCallback? onTap;
  const _CardPasto({required this.card, this.destaque = _Destaque.nenhum, this.onTap});

  @override
  Widget build(BuildContext context) {
    final temAnimais = card.total > 0;
    final borda = switch (destaque) {
      _Destaque.destino => const BorderSide(color: Color(0xFF128CB8), width: 3),
      _Destaque.origem => const BorderSide(color: Color(0xFFFF8F00), width: 3),
      _Destaque.nenhum => BorderSide.none,
    };

    return Material(
      color: card.cor,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(5),
        side: borda,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 3),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0x1F808080), width: 1),
                    ),
                  ),
                  child: Text(
                    card.pasto.descricao,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0x99000000),
                    ),
                  ),
                ),
                if (temAnimais)
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              if (card.bezerros > 0)
                                _QtdIcone('mapa_bezerro.png', card.bezerros),
                              if (card.femeas > 0)
                                _QtdIcone('mapa_vaca.png', card.femeas),
                              if (card.machos > 0)
                                _QtdIcone('mapa_gado.png', card.machos),
                            ],
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 50,
                          color: const Color(0x33000000),
                        ),
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${card.total}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  color: Color(0xCC000000),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (!card.entradaSaida && card.pasto.capim.isNotEmpty)
              Positioned(
                right: 4,
                bottom: 2,
                left: 4,
                child: Text(
                  card.pasto.capim,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8, color: Color(0x73000000)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QtdIcone extends StatelessWidget {
  final String imagem;
  final int qtd;
  const _QtdIcone(this.imagem, this.qtd);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/images/$imagem', width: 27, height: 16),
        const SizedBox(width: 4),
        Text(
          '$qtd',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xCC000000),
          ),
        ),
      ],
    );
  }
}
