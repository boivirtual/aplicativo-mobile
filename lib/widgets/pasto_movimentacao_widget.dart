import 'package:flutter/material.dart';

import '../data/daos/mapa_gado_dao.dart';
import '../screens/composicao_descricao_lote_screen.dart';
import '../screens/morte_animal_modal.dart';
import '../screens/nutricao_pasto_modal.dart';
import '../services/mapa_gado_sync_service.dart';
import '../utils/app_alert.dart';
import '../utils/mapa_tabuleiro_calculo.dart';
import '../utils/pasto_movimentacao_calculo.dart';
import 'seletor_campo_widget.dart';

/// "Mapa de Gado - Movimentações" — tela do pasto aberta pelo toque no
/// pasto (Tabuleiro ou Satélite). Mesmos dados de
/// form_mapa_gados_movimentacao.php (sistema web), no layout do modelo do
/// app e no padrão visual da Pesagem: tarja azul (fazenda, pasto - capim,
/// animais há quantos dias, lotação Kg/Ha), tabela por faixa de idade,
/// transferência, descrição do lote e as outras atividades.
///
/// O toque no campo "Descrição do Lote" abre a Composição da Descrição do
/// Lote em modo de edição (igual ao web). O Confirma transfere os animais
/// da categoria para o Novo Pasto e abre a Composição da Descrição do Lote
/// do pasto destino quando o web abre (ver [_confirmarTransferencia]). O
/// botão Morte abre o modal "Mapa de Gado - Morte" ([MorteAnimalModal]).
/// O botão Nutrição abre "Mapa de Gado - Nutrição" ([NutricaoPastoModal]).
/// Nascimento ainda não faz nada (próxima etapa).
///
/// Lê tudo do cache local (funciona offline).
class PastoMovimentacaoWidget extends StatefulWidget {
  final String bd;
  final int fazendaId;

  /// Id da fazenda como vem do login ("000000056") — chave do cadastro
  /// de animais guardado no aparelho (botão Morte).
  final String fazendaCodigo;
  final String nomeFazenda;
  final int pastoId;
  final String? usuario;

  const PastoMovimentacaoWidget({
    super.key,
    required this.bd,
    required this.fazendaId,
    required this.fazendaCodigo,
    required this.nomeFazenda,
    required this.pastoId,
    required this.usuario,
  });

  @override
  State<PastoMovimentacaoWidget> createState() =>
      _PastoMovimentacaoWidgetState();
}

class _PastoMovimentacaoWidgetState extends State<PastoMovimentacaoWidget> {
  static const _azul = Color(0xFF1E6FB5);
  static const _laranja = Color(0xFFD5641C);
  static const _cinza = Color(0xFF6B6B6B);

  /// Cores dos botões da Pesagem (ConfirmButtonPesagemWidget).
  static const _verdeBotao = Color(0xFF4CAF50);

  /// Azul do botão "Nova Pesagem" (pesagem_screen.dart).
  static const _azulBotao = Color(0xFF007AFF);

  /// Cor do rótulo dos campos da Pesagem (corDoRotulo).
  static final Color _corRotulo = Colors.blueGrey[800]!;

  bool _carregando = true;
  PastoMapa? _pasto;
  int _total = 0;
  int? _kgHa;
  List<LinhaAnimaisPasto> _linhas = [];
  List<PastoMapa> _pastosDestino = [];
  List<OpcaoCategoriaSexo> _opcoesCategoria = [];

  int? _novoPasto;
  String? _categoria;
  final _qtdController = TextEditingController();
  final _loteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Relê quando a fila do mapa envia algo (ex: o número do lote chega do
    // servidor com a tela aberta).
    MapaGadoSyncService.instance.versaoFila.addListener(_carregar);
    _carregar();
  }

  @override
  void dispose() {
    MapaGadoSyncService.instance.versaoFila.removeListener(_carregar);
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
      _opcoesCategoria = PastoMovimentacaoCalculo.opcoesTransferencia(
        animaisDoPasto: doPasto,
        categorias: categorias,
      );
      _carregando = false;
    });
  }

  /// Toque no campo "Descrição do Lote" — igual ao web
  /// (abrir_modal_descricao_lote(0) + gravar_alterar_descricao_lote.php
  /// com novo_id = 'N'): edita os lotes do pasto e mantém o número do
  /// lote. Grava no cache na hora e entra na fila (funciona offline).
  Future<void> _editarDescricaoLote() async {
    final pasto = _pasto;
    if (pasto == null) return;
    final dao = MapaGadoDao.instance;
    final descricoes = await dao.descricoesLote(widget.bd);
    final lotes = await dao.lotesDoPasto(widget.bd, pasto.id);
    if (!mounted) return;
    final resultado = await showDialog<NovaDescricaoLote>(
      context: context,
      barrierDismissible: false,
      requestFocus: false,
      builder: (_) => ComposicaoDescricaoLoteScreen(
        nomePasto: pasto.descricao,
        descricaoAtual: pasto.descricaoLote,
        descricoes: descricoes,
        edicao: true,
        lotesAtuais: lotes,
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    if (resultado == null || !mounted) return; // Voltar

    await MapaGadoSyncService.instance.gravarDescricaoLote(
      bd: widget.bd,
      pasto: pasto.id,
      descricaoLote: resultado.descricao,
      lotes: resultado.lotes,
      usuario: widget.usuario,
      manterNumero: true,
    );
    await _carregar();
  }

  /// Botão Nutrição — modal "Mapa de Gado - Nutrição" do web.
  Future<void> _abrirNutricao() async {
    final pasto = _pasto;
    if (pasto == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NutricaoPastoModal(
        bd: widget.bd,
        fazendaId: widget.fazendaId,
        nomeFazenda: widget.nomeFazenda,
        pastoId: pasto.id,
        nomePasto: pasto.descricao,
        totalAnimais: _total,
        usuario: widget.usuario,
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// Botão Morte — modal "Mapa de Gado - Morte" do web. Por enquanto só o
  /// controle de estoque por animal ('I').
  Future<void> _abrirMorte() async {
    final pasto = _pasto;
    if (pasto == null) return;
    final controle = await MapaGadoDao.instance.controleEstoque(widget.bd);
    if (!mounted) return;
    if (controle == 'L') {
      await AppAlert.erro(
        context,
        'A Morte pelo aplicativo ainda está disponível só para o controle '
        'de estoque por animal.',
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MorteAnimalModal(
        bd: widget.bd,
        fazendaId: widget.fazendaId,
        fazendaCodigo: widget.fazendaCodigo,
        nomeFazenda: widget.nomeFazenda,
        pastoId: pasto.id,
        nomePasto: pasto.descricao,
        usuario: widget.usuario,
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await _carregar();
  }

  /// Botão Confirma — igual ao web (retirar_por_categoria +
  /// gravar_retirar_categoria + exibe_opcoes_desc_lote_pasto_destino):
  ///   1. valida os campos, com as mesmas mensagens;
  ///   2. pergunta "Mover TODOS os animais..." ou "Mover N animais da
  ///      Categoria...";
  ///   3. transfere (cache na hora + fila, funciona offline);
  ///   4. origem ficou vazia e o destino não tinha descrição: nada mais a
  ///      fazer (a descrição foi junto — Premissa 1);
  ///   5. senão abre a Composição da Descrição do Lote do pasto destino:
  ///      destino sem descrição -> Criar nova / Levar; com descrição ->
  ///      Manter / Criar nova.
  Future<void> _confirmarTransferencia() async {
    final pasto = _pasto;
    if (pasto == null) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final opcao = _opcoesCategoria
        .where((o) => o.rotulo == _categoria)
        .firstOrNull;
    final quantidade = int.tryParse(_qtdController.text.trim()) ?? 0;
    final destino = _pastosDestino.where((p) => p.id == _novoPasto).firstOrNull;

    String? erro;
    if (opcao == null) {
      erro = 'Selecione a Qual Categoria.';
    } else if (quantidade <= 0) {
      erro = 'Informe a Quantidade para transferir.';
    } else if (destino == null) {
      erro = 'Selecione o Novo Pasto.';
    } else if (pasto.descricaoLote.trim().isEmpty) {
      erro = 'Informe a Descrição do Lote.';
    } else if (quantidade > opcao.quantidade) {
      erro =
          'A quantidade de animais para transferir da categoria '
          '${opcao.rotulo} é insuficiente.';
    }
    if (erro != null || opcao == null || destino == null) {
      await AppAlert.erro(context, erro ?? '');
      return;
    }

    final todos = quantidade == _total;
    final ok = await perguntarSimNao(
      context,
      titulo: 'Mapa de Gado - Mensagem',
      mensagem: todos
          ? 'Mover TODOS os animais do pasto ${pasto.descricao} para o '
                'pasto ${destino.descricao}?'
          : 'Mover $quantidade animais da Categoria ${opcao.rotulo} para o '
                'Pasto ${destino.descricao}?',
    );
    if (!ok || !mounted) return;

    final destinoSemDescricaoAntes = destino.descricaoLote.isEmpty;

    await MapaGadoSyncService.instance.transferirCategoria(
      bd: widget.bd,
      origem: pasto.id,
      destino: destino.id,
      categoria: opcao.categoria,
      sexo: opcao.sexo,
      quantidade: quantidade,
      usuario: widget.usuario,
    );
    if (!mounted) return;
    setState(() {
      _categoria = null;
      _novoPasto = null;
      _qtdController.clear();
    });
    await _carregar();
    if (!mounted) return;

    // Origem ficou vazia e o destino não tinha descrição: pronto.
    if (todos && destinoSemDescricaoAntes) return;

    // Descrição do destino DEPOIS da transferência (o web usa a que o
    // servidor devolve).
    final dao = MapaGadoDao.instance;
    final destinoAgora = (await dao.pastos(
      widget.bd,
      widget.fazendaId,
      incluirForaTabuleiro: true,
    )).where((p) => p.id == destino.id).firstOrNull;
    final descricaoDestino = destinoAgora?.descricaoLote ?? '';
    final descricoes = await dao.descricoesLote(widget.bd);
    if (!mounted) return;

    final resultado = await showDialog<NovaDescricaoLote>(
      context: context,
      barrierDismissible: false,
      requestFocus: false,
      builder: (_) => ComposicaoDescricaoLoteScreen(
        nomePasto: destino.descricao,
        descricaoAtual: descricaoDestino,
        descricoes: descricoes,
        mostrarManter: descricaoDestino.isNotEmpty,
        mostrarLevar: descricaoDestino.isEmpty,
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    if (resultado == null || !mounted) return; // Manter

    if (resultado.levar) {
      await MapaGadoSyncService.instance.levarDescricaoLote(
        bd: widget.bd,
        origem: pasto.id,
        destino: destino.id,
        usuario: widget.usuario,
      );
    } else {
      await MapaGadoSyncService.instance.gravarDescricaoLote(
        bd: widget.bd,
        pasto: destino.id,
        descricaoLote: resultado.descricao,
        lotes: resultado.lotes,
        usuario: widget.usuario,
      );
    }
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    final pasto = _pasto;
    if (pasto == null) {
      return const Center(child: Text('Pasto não encontrado neste aparelho.'));
    }

    return Container(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 16),
        children: [
          _cabecalho(pasto),
          const SizedBox(height: 22),
          _tabela(),
          const SizedBox(height: 12),
          _formulario(),
          const SizedBox(height: 22),
          _outrasAtividades(),
        ],
      ),
    );
  }

  /// Tarja azul no mesmo padrão da Pesagem (FiltroAtivoPesagemWidget),
  /// sem o ícone de edição.
  Widget _cabecalho(PastoMapa pasto) {
    final dias = _total > 0
        ? PastoMovimentacaoCalculo.dias(pasto.dataComAnimais)
        : PastoMovimentacaoCalculo.dias(pasto.dataSemAnimais);
    final titulo = pasto.capim.isEmpty
        ? pasto.descricao
        : '${pasto.descricao} - ${pasto.capim}';
    // "77 Animais há 5 dia(s)  -  Lotação: 3.306 Kg/Ha" (o web só mostra a
    // lotação quando tem animal e peso)
    final lotacao = _kgHa == null
        ? ''
        : '  -  Lotação: ${PastoMovimentacaoCalculo.milhar(_kgHa!)} Kg/Ha';

    TextStyle estilo(double tamanho) => TextStyle(
      fontSize: tamanho,
      color: Colors.blue,
      fontWeight: FontWeight.bold,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            widget.nomeFazenda,
            textAlign: TextAlign.center,
            style: estilo(11),
          ),
          const SizedBox(height: 2),
          Text(titulo, textAlign: TextAlign.center, style: estilo(14)),
          const SizedBox(height: 2),
          Text.rich(
            textAlign: TextAlign.center,
            TextSpan(
              style: estilo(12),
              children: _total > 0
                  ? [
                      // quantidade em destaque (mesmo negrito engrossado
                      // do total da tarja do Mapa de Gado)
                      TextSpan(
                        text: '$_total Animais',
                        style: const TextStyle(
                          shadows: [
                            Shadow(color: Colors.blue, offset: Offset(0.5, 0)),
                            Shadow(color: Colors.blue, offset: Offset(-0.5, 0)),
                            Shadow(color: Colors.blue, offset: Offset(0, 0.5)),
                          ],
                        ),
                      ),
                      TextSpan(text: ' há $dias dia(s)$lotacao'),
                    ]
                  : [TextSpan(text: 'Pasto vazio há $dias dia(s)')],
            ),
          ),
        ],
      ),
    );
  }

  /// Negrito de verdade: a fonte do app (FuturaStd) só tem a versão Light,
  /// então o traço é engrossado com "sombras" da mesma cor (mesmo recurso
  /// da tarja do Mapa de Gado).
  static TextStyle _negrito(Color cor, double tamanho) => TextStyle(
    fontSize: tamanho,
    color: cor,
    fontWeight: FontWeight.bold,
    shadows: [
      Shadow(color: cor, offset: const Offset(0.35, 0)),
      Shadow(color: cor, offset: const Offset(-0.35, 0)),
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
          style: _negrito(cor, 9.5),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 6),
            decoration: const BoxDecoration(border: Border(bottom: divisor)),
            child: Row(
              children: [
                Expanded(child: Text('MACHOS', style: _negrito(_azul, 13))),
                Expanded(child: Text('FÊMEAS', style: _negrito(_laranja, 13))),
                Expanded(child: Text('BEZERROS', style: _negrito(_cinza, 13))),
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

  // ---------------------------------------------------------------------
  // Campos e botões no padrão da Pesagem (InputMinimalPesagemWidget /
  // ConfirmButtonPesagemWidget): fundo branco, sem borda, cantos 8, rótulo
  // azul acinzentado, dentro de um bloco cinza claro com cantos 12; botões
  // com cantos 10 e texto branco.
  // ---------------------------------------------------------------------

  InputDecoration _decoracao(String rotulo) => InputDecoration(
    labelText: rotulo,
    labelStyle: TextStyle(fontSize: 14, color: _corRotulo),
    border: InputBorder.none,
    // compacto para o rótulo flutuante + o valor caberem nos 56 de altura
    isDense: true,
    contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
  );

  Widget _campo(Widget child) => Container(
    height: 56,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );

  Widget _botao(
    String texto,
    Color cor, {
    double fonte = 18,
    double altura = 54,
    VoidCallback? aoTocar,
  }) => SizedBox(
    height: altura,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: cor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      // Sem [aoTocar]: funcionalidade das próximas etapas.
      onPressed: aoTocar ?? () {},
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          texto,
          style: TextStyle(color: Colors.white, fontSize: fonte),
        ),
      ),
    ),
  );

  Widget _formulario() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              'Transferir animais de pasto?',
              style: TextStyle(fontSize: 15, color: _corRotulo),
            ),
          ),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: SeletorCampoWidget<String>(
                  rotulo: 'Qual Categoria',
                  corRotulo: _corRotulo,
                  valor: _categoria,
                  opcoes: [
                    for (final c in _opcoesCategoria)
                      MapEntry(c.rotulo, c.rotulo),
                  ],
                  onChanged: (v) => setState(() => _categoria = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _campo(
                  TextFormField(
                    controller: _qtdController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 16),
                    decoration: _decoracao('Quantidade'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Mesmas proporções da linha de cima (5/3): Novo Pasto com a
              // largura de Qual Categoria e Confirma com a de Quantidade.
              Expanded(
                flex: 5,
                child: SeletorCampoWidget<int>(
                  rotulo: 'Novo Pasto',
                  corRotulo: _corRotulo,
                  valor: _novoPasto,
                  opcoes: [
                    for (final p in _pastosDestino) MapEntry(p.id, p.descricao),
                  ],
                  onChanged: (v) => setState(() => _novoPasto = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _botao(
                  'Confirma',
                  _verdeBotao,
                  altura: 56,
                  aoTocar: _confirmarTransferencia,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Lote: o toque abre a Composição da Descrição do Lote.
          _campo(
            TextFormField(
              controller: _loteController,
              readOnly: true,
              onTap: _editarDescricaoLote,
              style: const TextStyle(fontSize: 15),
              decoration: _decoracao('Descrição do Lote'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _outrasAtividades() {
    return Column(
      children: [
        Text(
          'Outras Atividades',
          style: TextStyle(fontSize: 14, color: _corRotulo),
        ),
        const Divider(indent: 8, endIndent: 8, color: Color(0xFFDDDDDD)),
        Row(
          children: [
            Expanded(
              child: _botao(
                'Nutrição',
                _azulBotao,
                fonte: 16,
                aoTocar: _abrirNutricao,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _botao('Nascimento', _azulBotao, fonte: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: _botao(
                'Morte',
                _azulBotao,
                fonte: 16,
                aoTocar: _abrirMorte,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
