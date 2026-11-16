import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/daos/mapa_gado_dao.dart';
import '../utils/app_alert.dart';
import '../utils/rolar_ate_foco.dart';
import '../widgets/campo_topo_widget.dart';

/// Modal "Mistura(s)" do Resumo Diário (Seção 5 — Nutrição e Misturas, card
/// "Adicionar Mistura"). Mesmo visual do modal "Aplicação de Remédio(s)" da
/// Seção 4: fundo cinza, (x) no canto e o conteúdo com rolagem.
///
/// Primeiro o select "Mistura" (opções: os produtos do select Produto da
/// Nutrição do Mapa de Gado, guardados no aparelho); escolhida, aparecem os
/// itens — por enquanto os mesmos produtos — cada um com a sua quantidade.
/// "Concluir Mistura" guarda a mistura (com o nome dela) na lista abaixo do
/// botão (editar e excluir, a última no topo) e limpa tudo. Devolve
/// { misturas } ao fechar pelo (x).
class MisturaModal extends StatefulWidget {
  /// Empresa (CNPJ): os produtos vêm do Mapa de Gado guardado no aparelho.
  final String bd;

  /// Misturas já feitas (editar); null = nenhuma.
  final List<Map<String, dynamic>>? misturas;

  const MisturaModal({super.key, required this.bd, this.misturas});

  @override
  State<MisturaModal> createState() => _MisturaModalState();
}

class _MisturaModalState extends State<MisturaModal> {
  static const _azulTitulo = Color(0xFF18385F);
  static const _azulBotao = Color(0xFF007AFF);
  static const _verde = Color(0xFF4CAF50);
  static final _corRotulo = Colors.blueGrey[800]!;

  /// Produtos do select Produto da Nutrição (id, descricao, unidade).
  List<Map<String, dynamic>> _produtos = [];
  bool _carregando = true;

  /// Quantidade digitada de cada produto (pelo id).
  final Map<int, TextEditingController> _qtdes = {};

  /// Misturas já concluídas, na ordem em que foram feitas: cada uma com os
  /// itens { id, produto, qtde, unidade }.
  final List<Map<String, dynamic>> _misturas = [];

  /// Mistura da lista em edição (índice em [_misturas]); null = nova.
  int? _editando;

  /// Mistura escolhida no select "Mistura" (id do produto da Nutrição) e se
  /// a lista do select está aberta.
  int? _misturaId;
  bool _misturaAberta = false;

  String? get _nomeMistura => _produtos
      .where((p) => p['id'] == _misturaId)
      .map((p) => '${p['descricao']}')
      .firstOrNull;

  final _rolagem = ScrollController();

  @override
  void initState() {
    super.initState();
    for (final m in widget.misturas ?? const []) {
      _misturas.add(Map<String, dynamic>.from(m));
    }
    _carregarProdutos();
  }

  Future<void> _carregarProdutos() async {
    final lista = await MapaGadoDao.instance.produtosNutricao(widget.bd);
    if (!mounted) return;
    setState(() {
      _produtos = lista;
      for (final p in lista) {
        _qtdes[p['id'] as int] = TextEditingController();
      }
      _carregando = false;
    });
  }

  @override
  void dispose() {
    for (final c in _qtdes.values) {
      c.dispose();
    }
    _rolagem.dispose();
    super.dispose();
  }

  /// 12,5 -> 12.5 (vírgula como separador).
  static double _numero(String texto) =>
      double.tryParse(texto.trim().replaceAll(',', '.')) ?? 0;

  /// Itens da mistura da tela: só os produtos com quantidade.
  List<Map<String, dynamic>> _itensDaTela() => [
    for (final p in _produtos)
      if (_numero(_qtdes[p['id']]?.text ?? '') > 0)
        {
          'id': p['id'],
          'produto': p['descricao'],
          'qtde': _qtdes[p['id']]!.text.trim(),
          'unidade': p['unidade'],
        },
  ];

  void _limparQtdes() {
    for (final c in _qtdes.values) {
      c.clear();
    }
  }

  /// "Concluir Mistura" (ou "Confirmar Edição"): guarda a mistura na lista
  /// (ou grava a editada) e limpa as quantidades.
  Future<void> _concluir() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_misturaId == null) {
      await AppAlert.erro(context, 'Selecione a Mistura.');
      return;
    }
    final itens = _itensDaTela();
    if (itens.isEmpty) {
      await AppAlert.erro(context, 'Informe a quantidade de algum produto.');
      return;
    }
    setState(() {
      final mistura = <String, dynamic>{
        'mistura_id': _misturaId,
        'mistura': _nomeMistura,
        'itens': itens,
      };
      if (_editando != null) {
        _misturas[_editando!] = mistura;
        _editando = null;
      } else {
        _misturas.add(mistura);
      }
      _limparQtdes();
      // a próxima começa pela escolha da mistura
      _misturaId = null;
    });
  }

  /// Editar uma mistura da lista: as quantidades dela voltam para os
  /// produtos.
  void _editar(int n) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _editando = n;
      _limparQtdes();
      _misturaId = _misturas[n]['mistura_id'] as int?;
      _misturaAberta = false;
      for (final i in (_misturas[n]['itens'] as List)) {
        _qtdes[(i as Map)['id']]?.text = '${i['qtde']}';
      }
    });
    _rolagem.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _cancelarEdicao() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _editando = null;
      _limparQtdes();
      _misturaId = null;
    });
  }

  /// Excluir uma mistura da lista (pergunta antes).
  Future<void> _excluir(int n) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Excluir Mistura',
          style: TextStyle(fontSize: 17, color: _azulTitulo),
        ),
        content: Text('Excluir a mistura ${_rotuloMistura(n)}?'),
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
      // excluiu a que estava em edição: sai da edição
      if (_editando == n) {
        _editando = null;
        _limparQtdes();
        _misturaId = null;
      }
      _misturas.removeAt(n);
      if (_editando != null && _editando! > n) _editando = _editando! - 1;
    });
  }

  /// Nome da mistura na lista (ou "Mistura N" nas antigas, sem nome).
  String _rotuloMistura(int n) =>
      '${_misturas[n]['mistura'] ?? 'Mistura ${n + 1}'}';

  /// Um produto: o nome com a unidade em cima, em negrito, e o campo da
  /// quantidade embaixo, na largura toda.
  Widget _linhaProduto(Map<String, dynamic> p) {
    final unidade = (p['unidade'] ?? '').toString().trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              '${p['descricao']} (${unidade.isEmpty ? 'kg' : unidade})',
              style: TextStyle(
                fontFamily: 'FuturaStdMedium',
                fontSize: 14,
                color: _corRotulo,
                shadows: [
                  Shadow(color: _corRotulo, offset: const Offset(0.4, 0)),
                ],
              ),
            ),
          ),
          CampoTextoTopo(
            rotulo: 'Quantidade',
            corRotulo: _corRotulo,
            controller: _qtdes[p['id']]!,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
            ],
          ),
        ],
      ),
    );
  }

  /// Select "Mistura" com a lista aberta embaixo do próprio campo: as opções
  /// são os produtos da Nutrição; o toque escolhe e fecha.
  Widget _selectMistura() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CampoValorTopo(
        rotulo: 'Mistura',
        corRotulo: _corRotulo,
        valor: _nomeMistura ?? '',
        icone: Icon(
          _misturaAberta ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          color: _corRotulo,
        ),
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() => _misturaAberta = !_misturaAberta);
        },
      ),
      if (_misturaAberta)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 5 * 44 + 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFCFD8DC)),
          ),
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
              itemExtent: 44,
              itemCount: _produtos.length,
              itemBuilder: (context, i) {
                final p = _produtos[i];
                final marcado = p['id'] == _misturaId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Material(
                    color: marcado
                        ? const Color(0xFFD6E8FA)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() {
                        _misturaId = p['id'] as int;
                        _misturaAberta = false;
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${p['descricao']}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: marcado ? _azulTitulo : Colors.black87,
                                ),
                              ),
                            ),
                            if (marcado)
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
                );
              },
            ),
          ),
        ),
    ],
  );

  /// Ícone de editar/excluir da lista, no azul do btn-primary.
  Widget _iconeLista(IconData icone, VoidCallback aoTocar) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: aoTocar,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Icon(icone, size: 18, color: _azulBotao),
    ),
  );

  /// Lista das misturas, com rolagem, da última para a primeira: o nome da
  /// mistura, os produtos e os ícones de editar e excluir.
  Widget _listaMisturas() {
    final estilo = TextStyle(fontSize: 11, color: _corRotulo);
    final linhas = <TableRow>[];
    for (var n = _misturas.length - 1; n >= 0; n--) {
      final itens = (_misturas[n]['itens'] as List)
          .map((i) => '${(i as Map)['produto']}')
          .join(', ');
      linhas.add(
        TableRow(
          // a mistura em edição fica em azul claro
          decoration: n == _editando
              ? BoxDecoration(
                  color: const Color(0xFFD6E8FA),
                  borderRadius: BorderRadius.circular(4),
                )
              : null,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Text(_rotuloMistura(n), style: estilo),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Text(itens, style: estilo),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _iconeLista(Icons.edit_outlined, () => _editar(n)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
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
            // os produtos ficam com o que sobrar (quebra se precisar)
            columnWidths: const {1: FlexColumnWidth()},
            children: linhas,
          ),
        ),
      ),
    );
  }

  /// Botão do modal (Concluir / Confirmar Edição / Cancelar).
  Widget _botao(
    String texto,
    VoidCallback aoTocar, {
    Color cor = _verde,
    Color corTexto = Colors.white,
  }) => SizedBox(
    height: 46,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: cor,
        foregroundColor: corTexto,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: aoTocar,
      child: Text(texto, style: const TextStyle(fontSize: 15)),
    ),
  );

  bool _tecladoAntes = false;

  @override
  Widget build(BuildContext context) {
    final tecladoAberto = MediaQuery.viewInsetsOf(context).bottom > 0;
    // teclado acabou de abrir: leva o campo em edição para a parte visível
    if (tecladoAberto && !_tecladoAntes) rolarAteCampoEmFoco();
    _tecladoAntes = tecladoAberto;
    return Dialog(
      backgroundColor: Colors.transparent,
      // centralizado na tela do celular
      alignment: Alignment.center,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 44, 6),
                  child: Text(
                    _editando == null
                        ? 'Mistura(s)'
                        : '${_rotuloMistura(_editando!)} — editando',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, color: _azulTitulo),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    controller: _rolagem,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      4,
                      12,
                      tecladoAberto ? 160 : 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_carregando)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_produtos.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              'Os produtos da Nutrição ainda não foram '
                              'baixados neste aparelho. Abra o Mapa de Gado '
                              'com internet e tente de novo.',
                              style: TextStyle(fontSize: 14, color: _corRotulo),
                            ),
                          )
                        else ...[
                          _selectMistura(),
                          const SizedBox(height: 14),
                          // os itens só depois de escolher a mistura (por
                          // enquanto todos os produtos da Nutrição)
                          if (_misturaId != null) ...[
                            for (final p in _produtos) _linhaProduto(p),
                            const SizedBox(height: 6),
                            if (_editando == null)
                              _botao('Concluir Mistura', _concluir)
                            else
                              Row(
                                children: [
                                  Expanded(
                                    child: _botao(
                                      'Confirmar Edição',
                                      _concluir,
                                      cor: _azulBotao,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _botao(
                                      'Cancelar',
                                      _cancelarEdicao,
                                      cor: const Color(0xFFE9ECEF),
                                      corTexto: const Color(0xFF333333),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                          if (_misturas.isNotEmpty) _listaMisturas(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // (x) no canto: fecha; as misturas da lista valem do jeito que
          // estão (só as quantidades ainda não concluídas se perdem)
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
                onTap: () => Navigator.pop(context, <String, dynamic>{
                  'misturas': _misturas,
                }),
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
