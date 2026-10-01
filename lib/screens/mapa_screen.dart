import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/daos/mapa_gado_dao.dart';
import '../services/mapa_gado_sync_service.dart';
import '../utils/mapa_tabuleiro_calculo.dart';
import '../widgets/cabecalho_fazenda_widget.dart';
import '../widgets/indicador_conectividade_widget.dart';

/// Mapa de Gado — visão Tabuleiro, igual à primeira tela do sistema web
/// (form_mapa_gados.php + ler_mapa_gados.php): um card por pasto, pastos
/// de ENTRADA/SAÍDA primeiro (em branco), depois os demais coloridos por
/// módulo, com bezerros/fêmeas/machos, total do pasto, tipo de capim,
/// total de animais da fazenda e busca por nome do pasto.
///
/// Offline-first: a tela sempre lê do cache local (ver MapaGadoDao) e as
/// contagens são calculadas na hora (MapaTabuleiroCalculo), então continua
/// funcionando sem internet. O cache é atualizado na abertura do app
/// (AtualizandoDadosScreen), ao abrir esta tela e no "puxar pra atualizar".
class MapaScreen extends StatefulWidget {
  final VoidCallback onBack;
  const MapaScreen({super.key, required this.onBack});

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  String? fazendaSelecionada;
  List<dynamic> fazendasCarregadas = [];
  bool carregando = true;

  String? _bd;
  List<PastoTabuleiro> _cards = [];
  DateTime? _atualizadoEm;
  bool _lendoCache = false;
  bool _baixando = false;

  final _buscaController = TextEditingController();
  String _termoBusca = '';

  @override
  void initState() {
    super.initState();
    _carregarContexto();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _carregarContexto() async {
    final prefs = await SharedPreferences.getInstance();
    final fazendasJson = prefs.getString('userFazendas');
    setState(() {
      _bd = prefs.getString('userCNPJ');
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
    });
    _lerDoCache();
  }

  /// Baixa o tabuleiro do servidor (melhor esforço — offline ou erro
  /// mantém o cache) e relê. Ao abrir a tela e no "puxar pra atualizar".
  Future<void> _baixarEAtualizar() async {
    if (_bd == null || _idsFazendas.isEmpty) return;
    setState(() => _baixando = true);
    final ok = await MapaGadoSyncService.instance.baixar(_bd, _idsFazendas);
    if (!mounted) return;
    setState(() => _baixando = false);
    if (ok) await _lerDoCache();
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

  int get _totalFazenda => _cards.fold(0, (soma, c) => soma + c.total);

  List<PastoTabuleiro> get _cardsFiltrados {
    if (_termoBusca.isEmpty) return _cards;
    final termo = _termoBusca.toUpperCase();
    return _cards
        .where((c) => c.pasto.descricao.toUpperCase().contains(termo))
        .toList();
  }

  String _formatarDataHora(DateTime d) {
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)}/${d.year} ${dois(d.hour)}:${dois(d.minute)}';
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
        backgroundColor: const Color(0xFF18385F),
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
                CabecalhoFazendaWidget(
                  fazendaSelecionada: fazendaSelecionada,
                  fazendasCarregadas: fazendasCarregadas,
                  onChanged: _selecionarFazenda,
                ),
                if (_baixando)
                  const LinearProgressIndicator(
                    minHeight: 2,
                    color: Color(0xFF18385F),
                    backgroundColor: Color(0xFFF1F3F6),
                  ),
                Expanded(child: _buildConteudo()),
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
        Expanded(
          child: RefreshIndicator(
            onRefresh: _baixarEAtualizar,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final colunas = _colunasPorLargura(constraints.maxWidth);
                return GridView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: colunas,
                    mainAxisExtent: 120,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: filtrados.length,
                  itemBuilder: (context, i) => _CardPasto(card: filtrados[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
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
              Text(
                'Total de animais: $_totalFazenda',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF455A64),
                ),
              ),
              const SizedBox(width: 12),
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
            ],
          ),
          if (_atualizadoEm != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Dados de ${_formatarDataHora(_atualizadoEm!)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Card de um pasto — mesma composição do web: nome no topo, à esquerda
/// os ícones de bezerro/vaca/boi com as quantidades (só os que têm
/// animal), linha vertical, total do pasto à direita e o tipo de capim no
/// canto inferior direito.
class _CardPasto extends StatelessWidget {
  final PastoTabuleiro card;
  const _CardPasto({required this.card});

  @override
  Widget build(BuildContext context) {
    final temAnimais = card.total > 0;

    return Material(
      color: card.cor,
      elevation: 2,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        // Abrir as funcionalidades do pasto: próxima etapa.
        onTap: () {},
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 3),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0x59000000), width: 1),
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
