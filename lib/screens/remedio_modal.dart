import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_alert.dart';
import '../utils/estilo_app.dart';
import '../utils/rolar_ate_foco.dart';
import '../widgets/campo_topo_widget.dart';

/// Modal "Aplicação de Remédio(s)" do Resumo Diário (Seção 4 — Atividades do
/// Curral, card "Aplicamos Remédio(s)"). Mesmo visual do modal de Tratamento
/// da Seção 5: fundo cinza, (x) no canto para fechar sem gravar nada e o
/// conteúdo com rolagem.
///
/// Campos: Categoria Animal (uma só), Qtde Animais e, com 1 animal, o Id do
/// Brinco (opcional); Tipo; Nome do Produto; Sintoma (vários, opcional);
/// Qtde/Cabeça e Unidade. Devolve os dados ao confirmar; null pelo (x).
class RemedioModal extends StatefulWidget {
  /// Dados já informados (editar); null = novo.
  final Map<String, dynamic>? dados;

  const RemedioModal({super.key, this.dados});

  @override
  State<RemedioModal> createState() => _RemedioModalState();
}

class _RemedioModalState extends State<RemedioModal> {
  static const _azulTitulo = Color(0xFF18385F);
  static const _azulBotao = Color(0xFF007AFF);
  static const _verde = Color(0xFF4CAF50);
  static final _corRotulo = Colors.blueGrey[800]!;

  // as mesmas categorias do modal de Tratamento (Seção 5)
  static const _categorias = [
    'Bezerros 0–7m',
    'Bezerros 8–12m',
    'Novilhas 13–24m',
    'Garrotes 13–24m',
    'Vacas',
    'Bois',
    'CAVALOS',
  ];

  static const _tipos = [
    'Vacina',
    'Vermífugo',
    'Carrapaticida',
    'Mosquicida',
    'Medicamento',
    'Reprodução',
  ];

  // os mesmos sintomas do modal de Tratamento (Seção 5)
  static const _sintomas = [
    'Apático',
    'Bicheira',
    'Diarreia',
    'Mancando',
    'Coriza / Tosse',
    'Outro',
  ];

  static const _unidades = ['ml', 'ml/Kg', 'Unidade'];

  String? _categoria;
  final _qtdeController = TextEditingController();
  final _brincoController = TextEditingController();
  String? _tipo;
  final _produtoController = TextEditingController();
  final Set<String> _sintomasMarcados = {};
  final _doseController = TextEditingController();
  String? _unidade;

  /// Remédios já guardados pelo "+ Medicamento" / "Outra Categoria" (cada um
  /// com a categoria e a qtde da hora), na ordem em que entraram.
  final List<Map<String, dynamic>> _aplicacoes = [];

  /// Select com a borda azul, indicando o próximo a preencher (Tipo depois do
  /// "+ Medicamento"; Categoria Animal depois do "Outra Categoria").
  String? _destacado;

  /// Remédio da lista em edição (índice em [_aplicacoes]); null = incluindo.
  /// Na edição só o grupo Remédio(s) muda; o que estava sendo digitado antes
  /// fica guardado em [_rascunho] e volta ao confirmar ou cancelar.
  int? _editando;
  Map<String, dynamic>? _rascunho;
  final _rolagem = ScrollController();

  @override
  void initState() {
    super.initState();
    final d = widget.dados;
    if (d != null) {
      for (final a in (d['aplicacoes'] as List? ?? const [])) {
        _aplicacoes.add(Map<String, dynamic>.from(a as Map));
      }
      _categoria = d['categoria']?.toString();
      _qtdeController.text = (d['qtde'] ?? '').toString();
      _brincoController.text = (d['brinco'] ?? '').toString();
      _tipo = d['tipo']?.toString();
      _produtoController.text = (d['produto'] ?? '').toString();
      _sintomasMarcados.addAll(List<String>.from(d['sintomas'] ?? []));
      _doseController.text = (d['dose'] ?? '').toString();
      _unidade = d['unidade']?.toString();
    }
  }

  @override
  void dispose() {
    _qtdeController.dispose();
    _brincoController.dispose();
    _produtoController.dispose();
    _doseController.dispose();
    _rolagem.dispose();
    super.dispose();
  }

  int get _qtde => int.tryParse(_qtdeController.text.trim()) ?? 0;

  /// O que falta para guardar o remédio da tela (null = pode guardar).
  String? get _faltaNoRemedio => _categoria == null
      ? 'Selecione a Categoria Animal.'
      : _qtde <= 0
      ? 'Informe a Qtde Animais.'
      : _tipo == null
      ? 'Selecione o Tipo.'
      : _produtoController.text.trim().isEmpty
      ? 'Informe o Nome do Produto.'
      : _doseController.text.trim().isEmpty
      ? 'Informe a Qtde/Cabeça.'
      : _unidade == null
      ? 'Selecione a Unidade.'
      : null;

  /// Algum campo do grupo Remédio(s) começado.
  bool get _remedioComecado =>
      _tipo != null ||
      _produtoController.text.trim().isNotEmpty ||
      _sintomasMarcados.isNotEmpty ||
      _doseController.text.trim().isNotEmpty ||
      _unidade != null;

  /// Guarda na lista o remédio da tela, com a categoria e a qtde da hora.
  void _guardarRemedio() {
    _aplicacoes.add(<String, dynamic>{
      'categoria': _categoria,
      'qtde': _qtde,
      // o brinco só vale para 1 animal
      'brinco': _qtde == 1 ? _brincoController.text.trim() : '',
      'tipo': _tipo,
      'produto': _produtoController.text.trim(),
      // na ordem das opções, não na ordem em que foram tocados
      'sintomas': [
        for (final s in _sintomas)
          if (_sintomasMarcados.contains(s)) s,
      ],
      'dose': _doseController.text.trim(),
      'unidade': _unidade,
    });
  }

  void _limparRemedio() {
    _tipo = null;
    _produtoController.clear();
    _sintomasMarcados.clear();
    _doseController.clear();
    _unidade = null;
  }

  /// "+ Medicamento": guarda o remédio, limpa só o grupo Remédio(s) (a
  /// categoria fica) e destaca o Tipo para incluir o próximo.
  /// "Outra Categoria": guarda o remédio (se tiver um na tela — depois do
  /// "+ Medicamento" o grupo já está vazio e guardado), limpa tudo e destaca
  /// a Categoria.
  Future<void> _guardarE({required bool outraCategoria}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    // Outra Categoria com o grupo Remédio(s) vazio e algo já guardado: só
    // limpa e passa para a próxima categoria
    final guardar = !outraCategoria || _remedioComecado || _aplicacoes.isEmpty;
    final erro = guardar ? _faltaNoRemedio : null;
    if (erro != null) {
      await AppAlert.erro(context, erro);
      return;
    }
    setState(() {
      if (guardar) _guardarRemedio();
      _limparRemedio();
      _selectAberto = null;
      if (outraCategoria) {
        _categoria = null;
        _qtdeController.clear();
        _brincoController.clear();
        _destacado = 'Categoria Animal';
      } else {
        _destacado = 'Tipo';
      }
    });
  }

  Future<void> _confirmar() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_editando != null) {
      await AppAlert.erro(context, 'Confirme ou cancele a edição do remédio.');
      return;
    }
    // o remédio da tela entra junto (se começado, tem que estar completo)
    if (_remedioComecado || _aplicacoes.isEmpty) {
      final erro = _faltaNoRemedio;
      if (erro != null) {
        await AppAlert.erro(context, erro);
        return;
      }
      _guardarRemedio();
    }
    if (!mounted) return;
    Navigator.pop(context, <String, dynamic>{'aplicacoes': _aplicacoes});
  }

  /// Lista do que já foi guardado, com rolagem: a categoria e a qtde só na
  /// primeira linha de cada uma; depois o tipo e o nome do produto.
  Widget _listaAplicacoes() {
    final estilo = TextStyle(fontSize: 11, color: _corRotulo);
    final linhas = <TableRow>[];
    String? grupoAnterior;
    for (var n = 0; n < _aplicacoes.length; n++) {
      final a = _aplicacoes[n];
      final grupo = '${a['categoria']}|${a['qtde']}';
      final novo = grupo != grupoAnterior;
      grupoAnterior = grupo;
      final topo = novo && linhas.isNotEmpty ? 8.0 : 2.0;
      linhas.add(
        TableRow(
          // a linha em edição fica em azul claro
          decoration: n == _editando
              ? BoxDecoration(
                  color: const Color(0xFFD6E8FA),
                  borderRadius: BorderRadius.circular(4),
                )
              : null,
          children: [
            Padding(
              padding: EdgeInsets.only(top: topo, right: 8),
              child: Text(
                novo ? '${a['categoria']} - ${a['qtde']}' : '',
                style: estilo,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: topo, right: 8),
              child: Text('${a['tipo']}', style: estilo),
            ),
            Padding(
              padding: EdgeInsets.only(top: topo, right: 4),
              child: Text('${a['produto']}', style: estilo),
            ),
            Padding(
              padding: EdgeInsets.only(top: topo - 2),
              child: _iconeLista(Icons.edit_outlined, () => _editar(n)),
            ),
            Padding(
              padding: EdgeInsets.only(top: topo - 2),
              child: _iconeLista(Icons.delete_outline, () => _excluir(n)),
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 12),
      constraints: const BoxConstraints(maxHeight: 150),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            // o nome do produto fica com o que sobrar (quebra se precisar)
            columnWidths: const {2: FlexColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: linhas,
          ),
        ),
      ),
    );
  }

  /// Ícone de editar/excluir da lista, no azul do btn-primary.
  Widget _iconeLista(IconData icone, VoidCallback aoTocar) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: aoTocar,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Icon(icone, size: 18, color: _azulBotao),
    ),
  );

  /// Campos do grupo Remédio(s) da tela.
  Map<String, dynamic> _camposRemedio() => <String, dynamic>{
    'tipo': _tipo,
    'produto': _produtoController.text.trim(),
    // na ordem das opções, não na ordem em que foram tocados
    'sintomas': [
      for (final s in _sintomas)
        if (_sintomasMarcados.contains(s)) s,
    ],
    'dose': _doseController.text.trim(),
    'unidade': _unidade,
  };

  void _preencherRemedio(Map<String, dynamic> d) {
    _tipo = d['tipo']?.toString();
    _produtoController.text = (d['produto'] ?? '').toString();
    _sintomasMarcados
      ..clear()
      ..addAll(List<String>.from(d['sintomas'] ?? []));
    _doseController.text = (d['dose'] ?? '').toString();
    _unidade = d['unidade']?.toString();
  }

  /// Editar um remédio da lista: os campos dele vão para o grupo Remédio(s)
  /// (a categoria não muda); o que estava sendo digitado fica guardado.
  void _editar(int n) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _rascunho ??= _camposRemedio();
      _editando = n;
      _preencherRemedio(_aplicacoes[n]);
      _selectAberto = null;
      _destacado = null;
    });
  }

  /// Confirmar a edição: grava os campos do grupo Remédio(s) no remédio da
  /// lista e volta o que estava sendo digitado antes.
  Future<void> _confirmarEdicao() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final n = _editando;
    if (n == null) return;
    final erro = _tipo == null
        ? 'Selecione o Tipo.'
        : _produtoController.text.trim().isEmpty
        ? 'Informe o Nome do Produto.'
        : _doseController.text.trim().isEmpty
        ? 'Informe a Qtde/Cabeça.'
        : _unidade == null
        ? 'Selecione a Unidade.'
        : null;
    if (erro != null) {
      await AppAlert.erro(context, erro);
      return;
    }
    setState(() {
      _aplicacoes[n].addAll(_camposRemedio());
      _sairDaEdicao();
    });
  }

  /// Cancelar a edição (ou sair dela): a lista não muda e o que estava sendo
  /// digitado volta.
  void _sairDaEdicao() {
    _editando = null;
    _preencherRemedio(_rascunho ?? const {});
    _rascunho = null;
    _selectAberto = null;
  }

  /// Excluir um remédio da lista (pergunta antes).
  Future<void> _excluir(int n) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final a = _aplicacoes[n];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Excluir Remédio',
          style: TextStyle(fontSize: 17, color: _azulTitulo),
        ),
        content: Text(
          'Excluir ${a['tipo']} ${a['produto']} de ${a['categoria']}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('NÃO'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SIM'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      // excluiu o que estava em edição: sai da edição
      if (_editando == n) _sairDaEdicao();
      _aplicacoes.removeAt(n);
      if (_editando != null && _editando! > n) _editando = _editando! - 1;
    });
  }

  /// Botão de guardar (+ Medicamento / Outra Categoria): btn-info do app;
  /// [cor]/[corTexto] para os da edição (Confirmar / Cancelar).
  Widget _botaoGuardar(
    String texto,
    VoidCallback aoTocar, {
    Color cor = const Color(0xFF5BC0DE),
    Color corTexto = Colors.white,
  }) => SizedBox(
    height: 42,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: cor,
        foregroundColor: corTexto,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: aoTocar,
      child: Text(texto, style: const TextStyle(fontSize: 14)),
    ),
  );

  /// Título de um grupo de campos (Categoria, Remédio(s)): a mesma fonte do
  /// "Clique nas Atividades para Confirmar!" do Resumo (Medium com reforço).
  Widget _tituloGrupo(String texto) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 8),
    child: Text(
      texto,
      style: TextStyle(
        fontFamily: 'FuturaStdMedium',
        fontSize: 14,
        color: _corRotulo,
        shadows: [Shadow(color: _corRotulo, offset: const Offset(0.4, 0))],
      ),
    ),
  );

  /// Select aberto no próprio campo (só um por vez); null = todos fechados.
  String? _selectAberto;

  /// Select com a lista aberta embaixo do próprio campo (como o Responsável
  /// do Tratamento). De uma opção ([valor]/[aoEscolher]: Tipo, Unidade), o
  /// toque escolhe e fecha; de várias ([marcados]: Sintoma), o toque marca ou
  /// desmarca, a lista fica aberta e os marcados aparecem embaixo do campo.
  Widget _select(
    String rotulo,
    List<String> opcoes, {
    String? valor,
    ValueChanged<String>? aoEscolher,
    Set<String>? marcados,
  }) {
    final aberto = _selectAberto == rotulo;
    final destacado = _destacado == rotulo;
    final varios = marcados != null;
    final escolhidos = [
      for (final o in opcoes)
        if (varios ? marcados.contains(o) : o == valor) o,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // destacado: borda azul (a mesma do campo em edição)
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: EstiloApp.molduraCampo(ativo: destacado),
          child: CampoValorTopo(
            rotulo: rotulo,
            corRotulo: _corRotulo,
            valor: varios
                ? (escolhidos.isEmpty
                      ? ''
                      : '${escolhidos.length} selecionado(s)')
                : (valor ?? ''),
            icone: Icon(
              aberto ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              color: _corRotulo,
            ),
            onTap: () {
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() {
                _selectAberto = aberto ? null : rotulo;
                if (destacado) _destacado = null;
              });
            },
          ),
        ),
        if (aberto)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFCFD8DC)),
            ),
            child: Column(
              children: [
                for (final o in opcoes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Material(
                      color: escolhidos.contains(o)
                          ? const Color(0xFFD6E8FA)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => setState(() {
                          if (varios) {
                            if (!marcados.remove(o)) marcados.add(o);
                          } else {
                            aoEscolher?.call(o);
                            _selectAberto = null;
                          }
                        }),
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  o,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: escolhidos.contains(o)
                                        ? _azulTitulo
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              if (escolhidos.contains(o))
                                const Icon(
                                  Icons.check,
                                  size: 18,
                                  color: _azulBotao,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        // vários: os marcados embaixo do campo, como no Tratamento
        if (varios && escolhidos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              escolhidos.join(', '),
              // um pouco mais grosso que o texto normal (a fonte do app só tem
              // a versão fina: o traço é engrossado com uma "sombra" leve)
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.blue[300],
                shadows: [
                  Shadow(
                    color: Colors.blue[300]!,
                    offset: const Offset(0.4, 0),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  bool _tecladoAntes = false;

  @override
  Widget build(BuildContext context) {
    final tecladoAberto = MediaQuery.viewInsetsOf(context).bottom > 0;
    // teclado acabou de abrir: leva o campo em edição para a parte visível
    if (tecladoAberto && !_tecladoAntes) rolarAteCampoEmFoco();
    _tecladoAntes = tecladoAberto;
    return Dialog(
      backgroundColor: Colors.transparent,
      // mais para cima, aproveitando melhor a tela
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 14, 44, 6),
                  child: Text(
                    'Aplicação de Remédio(s)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: _azulTitulo),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    controller: _rolagem,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      4,
                      12,
                      tecladoAberto ? 160 : 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _tituloGrupo('Categoria'),
                        _select(
                          'Categoria Animal',
                          _categorias,
                          valor: _categoria,
                          aoEscolher: (v) => _categoria = v,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: CampoTextoTopo(
                                rotulo: 'Qtde Animais',
                                corRotulo: _corRotulo,
                                controller: _qtdeController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                // o Id do Brinco aparece/some conforme a qtde
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // só com 1 animal; ao lado da Qtde, não obrigatório
                            Expanded(
                              child: _qtde == 1
                                  ? CampoTextoTopo(
                                      rotulo: 'Id do Brinco',
                                      rotuloComplemento: '(opcional)',
                                      corRotulo: _corRotulo,
                                      controller: _brincoController,
                                      textCapitalization:
                                          TextCapitalization.characters,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _tituloGrupo(
                          _editando == null
                              ? 'Remédio(s)'
                              : 'Remédio(s) — editando',
                        ),
                        _select(
                          'Tipo',
                          _tipos,
                          valor: _tipo,
                          aoEscolher: (v) => _tipo = v,
                        ),
                        const SizedBox(height: 12),
                        // Nome do Produto e, embaixo, o Sintoma
                        CampoTextoTopo(
                          rotulo: 'Nome do Produto',
                          corRotulo: _corRotulo,
                          controller: _produtoController,
                          textCapitalization: TextCapitalization.characters,
                        ),
                        const SizedBox(height: 12),
                        _select(
                          'Sintoma',
                          _sintomas,
                          marcados: _sintomasMarcados,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: CampoTextoTopo(
                                rotulo: 'Qtde/Cabeça',
                                corRotulo: _corRotulo,
                                controller: _doseController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9,]'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _select(
                                'Unidade',
                                _unidades,
                                valor: _unidade,
                                aoEscolher: (v) => _unidade = v,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // editando um remédio da lista: Confirmar Edição / Cancelar
                        if (_editando != null)
                          Row(
                            children: [
                              Expanded(
                                child: _botaoGuardar(
                                  'Confirmar Edição',
                                  _confirmarEdicao,
                                  cor: _azulBotao,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _botaoGuardar(
                                  'Cancelar',
                                  () => setState(_sairDaEdicao),
                                  cor: const Color(0xFFE9ECEF),
                                  corTexto: const Color(0xFF333333),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: _botaoGuardar(
                                  '+ Medicamento',
                                  () => _guardarE(outraCategoria: false),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _botaoGuardar(
                                  'Outra Categoria',
                                  () => _guardarE(outraCategoria: true),
                                ),
                              ),
                            ],
                          ),
                        if (_aplicacoes.isNotEmpty) _listaAplicacoes(),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _verde,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _confirmar,
                      child: const Text(
                        'Encerrar Aplicação',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // (x) no canto: fecha sem gravar nada
          Positioned(
            top: -10,
            right: -10,
            child: Material(
              color: _azulTitulo,
              shape: const CircleBorder(
                side: BorderSide(color: Colors.white, width: 2),
              ),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
