import 'package:flutter/material.dart';

import '../data/daos/mapa_gado_dao.dart';
import '../utils/mapa_tabuleiro_calculo.dart';
import '../utils/pasto_movimentacao_calculo.dart';

/// "Mapa de Gado - Movimentações" — tela do pasto aberta pelo toque no
/// pasto (Tabuleiro ou Satélite). Mesmos dados de
/// form_mapa_gados_movimentacao.php (sistema web), no layout do modelo do
/// app: fazenda, pasto - capim, total de animais, há quantos dias, lotação
/// (Kg/Ha), tabela por faixa de idade, transferência, descrição do lote e
/// as outras atividades.
///
/// Por enquanto só exibe: Confirma da transferência, o lote e os botões
/// Nutrição/Nascimento/Morte ainda não fazem nada (próximas etapas).
///
/// Lê tudo do cache local (funciona offline).
class PastoMovimentacaoWidget extends StatefulWidget {
  final String bd;
  final int fazendaId;
  final String nomeFazenda;
  final int pastoId;

  const PastoMovimentacaoWidget({
    super.key,
    required this.bd,
    required this.fazendaId,
    required this.nomeFazenda,
    required this.pastoId,
  });

  @override
  State<PastoMovimentacaoWidget> createState() =>
      _PastoMovimentacaoWidgetState();
}

class _PastoMovimentacaoWidgetState extends State<PastoMovimentacaoWidget> {
  static const _azul = Color(0xFF1E6FB5);
  static const _laranja = Color(0xFFD5641C);
  static const _cinza = Color(0xFF6B6B6B);
  static const _verde = Color(0xFF4CD964);
  static const _azulBotao = Color(0xFF0A7AFF);
  static const _textoClaro = Color(0xFF7A7A7A);

  bool _carregando = true;
  PastoMapa? _pasto;
  int _total = 0;
  int? _kgHa;
  List<LinhaAnimaisPasto> _linhas = [];
  List<PastoMapa> _pastosDestino = [];
  List<String> _opcoesCategoria = [];

  int? _novoPasto;
  String? _categoria;
  final _qtdController = TextEditingController();
  final _loteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _qtdController.dispose();
    _loteController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final dao = MapaGadoDao.instance;
    final pastos = await dao.pastos(
      widget.bd,
      widget.fazendaId,
      incluirForaTabuleiro: true,
    );
    final categorias = await dao.categorias(widget.bd);
    final animais = await dao.animais(widget.bd, widget.fazendaId);
    final pesos = await dao.pesosMedios(widget.bd, widget.fazendaId);

    final pasto = pastos.where((p) => p.id == widget.pastoId).firstOrNull;
    final doPasto = animais.where((a) => a.pastoId == widget.pastoId).toList();

    if (!mounted) return;
    setState(() {
      _pasto = pasto;
      _total = doPasto.length;
      if (pasto != null) {
        _linhas = PastoMovimentacaoCalculo.linhas(
          pasto: pasto,
          animaisDoPasto: doPasto,
          categorias: categorias,
        );
        _kgHa = PastoMovimentacaoCalculo.kgHa(
          animaisDoPasto: doPasto,
          categorias: categorias,
          pesosMedios: pesos,
          area: pasto.area,
        );
        _loteController.text = PastoMovimentacaoCalculo.descricaoLoteComId(
          pasto,
        );
      }
      // "Novo Pasto": mesma lista/ordem do web (popular_select_pasto.php) —
      // pastos do Tabuleiro, sem o próprio pasto.
      _pastosDestino = pastos
          .where((p) => p.tabuleiro && p.id != widget.pastoId)
          .toList();
      _opcoesCategoria = PastoMovimentacaoCalculo.opcoesCategoriaSexo(
        animaisDoPasto: doPasto,
        categorias: categorias,
      );
      _carregando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    final pasto = _pasto;
    if (pasto == null) {
      return const Center(child: Text('Pasto não encontrado neste aparelho.'));
    }

    return Container(
      color: const Color(0xFFF5F5F5),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _cabecalho(pasto),
          const SizedBox(height: 10),
          _tabela(),
          const SizedBox(height: 14),
          _transferencia(),
          const SizedBox(height: 14),
          _lote(),
          const SizedBox(height: 26),
          _outrasAtividades(),
        ],
      ),
    );
  }

  Widget _cabecalho(PastoMapa pasto) {
    final dias = _total > 0
        ? PastoMovimentacaoCalculo.dias(pasto.dataComAnimais)
        : PastoMovimentacaoCalculo.dias(pasto.dataSemAnimais);
    final titulo = pasto.capim.isEmpty
        ? pasto.descricao
        : '${pasto.descricao} - ${pasto.capim}';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        children: [
          Text(
            widget.nomeFazenda,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: _textoClaro),
          ),
          const SizedBox(height: 2),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: _textoClaro),
          ),
          const SizedBox(height: 4),
          // "77 Animais há 5 dia(s)  -  Lotação: 3.306 Kg/Ha" (igual ao web,
          // que só mostra a lotação quando tem animal e peso)
          Text(
            _total > 0
                ? '$_total Animais há $dias dia(s)'
                      '${_kgHa == null ? '' : '  -  Lotação: ${PastoMovimentacaoCalculo.milhar(_kgHa!)} Kg/Ha'}'
                : 'Pasto vazio há $dias dia(s)',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
          ),
        ],
      ),
    );
  }

  /// Negrito de verdade: a fonte do app (FuturaStd) só tem a versão Light,
  /// então o traço é engrossado com "sombras" da mesma cor (mesmo recurso
  /// da tarja do Mapa de Gado).
  static TextStyle _negrito(Color cor) => TextStyle(
    fontSize: 13,
    color: cor,
    fontWeight: FontWeight.bold,
    shadows: [
      Shadow(color: cor, offset: const Offset(0.4, 0)),
      Shadow(color: cor, offset: const Offset(-0.4, 0)),
    ],
  );

  Widget _tabela() {
    const divisor = BorderSide(color: Color(0xFFDDDDDD));
    Widget celula(String? faixa, int? qtd, Color cor) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Text(
          faixa == null ? '' : '$faixa - $qtd',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: TextStyle(fontSize: 9.5, color: cor),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 6),
            decoration: const BoxDecoration(border: Border(bottom: divisor)),
            child: Row(
              children: [
                Expanded(child: Text('MACHOS', style: _negrito(_azul))),
                Expanded(child: Text('FÊMEAS', style: _negrito(_laranja))),
                Expanded(child: Text('BEZERROS', style: _negrito(_cinza))),
              ],
            ),
          ),
          for (final l in _linhas)
            Container(
              decoration: const BoxDecoration(border: Border(bottom: divisor)),
              child: Row(
                children: [
                  celula(l.faixaMacho, l.qtdMacho, _azul),
                  celula(l.faixaFemea, l.qtdFemea, _laranja),
                  celula(l.faixaBezerro, l.qtdBezerro, _cinza),
                ],
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _decoracao(String dica) => InputDecoration(
    hintText: dica,
    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFAAAAAA)),
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    border: const OutlineInputBorder(
      borderSide: BorderSide(color: Color(0xFFDDDDDD)),
    ),
    enabledBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: Color(0xFFDDDDDD)),
    ),
  );

  Widget _botaoConfirma() => SizedBox(
    height: 40,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: _verde,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      // Funcionalidade: próxima etapa.
      onPressed: () {},
      child: const Text('Confirma', style: TextStyle(fontSize: 14)),
    ),
  );

  Widget _transferencia() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFDDDDDD)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Transferir animais de pasto?',
                  style: TextStyle(fontSize: 15, color: Color(0xFF555555)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _novoPasto,
                  isExpanded: true,
                  decoration: _decoracao('Novo Pasto'),
                  hint: const Text(
                    'Novo Pasto',
                    style: TextStyle(fontSize: 13),
                  ),
                  items: _pastosDestino
                      .map(
                        (p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            p.descricao,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _novoPasto = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: DropdownButtonFormField<String>(
                  initialValue: _categoria,
                  isExpanded: true,
                  decoration: _decoracao('Categoria e Sexo'),
                  hint: const Text(
                    'Categoria e Sexo',
                    style: TextStyle(fontSize: 13),
                  ),
                  items: _opcoesCategoria
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, style: const TextStyle(fontSize: 13)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _categoria = v),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _qtdController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: _decoracao('Quantidade'),
                ),
              ),
              const SizedBox(width: 6),
              _botaoConfirma(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lote() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _loteController,
              // Montagem da descrição do lote: próxima etapa.
              readOnly: true,
              style: const TextStyle(fontSize: 13),
              decoration: _decoracao('Dê um nome para este lote de animais'),
            ),
          ),
          const SizedBox(width: 6),
          _botaoConfirma(),
        ],
      ),
    );
  }

  Widget _outrasAtividades() {
    Widget botao(String texto) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: SizedBox(
          height: 62,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _azulBotao,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // Cada atividade será feita numa etapa separada.
            onPressed: () {},
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(texto, style: const TextStyle(fontSize: 18)),
            ),
          ),
        ),
      ),
    );

    return Column(
      children: [
        const Text(
          'Outras Atividades',
          style: TextStyle(fontSize: 14, color: Color(0xFF666666)),
        ),
        const Divider(indent: 8, endIndent: 8, color: Color(0xFFDDDDDD)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [botao('Nutrição'), botao('Nascimento'), botao('Morte')],
          ),
        ),
      ],
    );
  }
}
