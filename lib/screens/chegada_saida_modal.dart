import 'package:flutter/material.dart';

import '../utils/app_alert.dart';
import '../utils/rolar_ate_foco.dart';
import '../widgets/campo_topo_widget.dart';

/// Modal "Chegada / Saída" do Resumo Diário (Seção 8 — Chegada e Saída de
/// Produtos, card "Adicionar Chegada ou Saída"). Mesmo visual e
/// funcionamento dos modais das Seções 5 a 7: fundo cinza, (x) no canto,
/// conteúdo com rolagem, botão verde que guarda o lançamento na lista de
/// baixo (editar e excluir, o último no topo).
///
/// Campos: Chegada ou Saída (uma, obrigatório), "De onde veio" (Chegada) ou
/// "Para onde foi" (Saída) e "Produtos e Quantidades", todos obrigatórios.
/// Devolve { movimentos } ao fechar pelo (x).
class ChegadaSaidaModal extends StatefulWidget {
  /// Lançamentos já incluídos (editar); null = nenhum.
  final List<Map<String, dynamic>>? movimentos;

  const ChegadaSaidaModal({super.key, this.movimentos});

  @override
  State<ChegadaSaidaModal> createState() => _ChegadaSaidaModalState();
}

class _ChegadaSaidaModalState extends State<ChegadaSaidaModal> {
  static const _azulTitulo = Color(0xFF18385F);
  static const _azulBotao = Color(0xFF007AFF);
  static const _verde = Color(0xFF4CAF50);
  static final _corRotulo = Colors.blueGrey[800]!;

  static const _opcoes = <(String, IconData)>[
    ('Chegada', Icons.move_to_inbox),
    ('Saída', Icons.outbox),
  ];

  String? _tipo;
  final _localController = TextEditingController();
  final _localFoco = FocusNode();
  final _produtosController = TextEditingController();
  final _produtosFoco = FocusNode();

  /// Lançamentos já confirmados, na ordem em que foram incluídos.
  final List<Map<String, dynamic>> _movimentos = [];

  /// Lançamento da lista em edição (índice em [_movimentos]); null = novo.
  int? _editando;

  final _rolagem = ScrollController();

  /// Rótulo do campo de origem/destino de acordo com a opção.
  String get _rotuloLocal =>
      _tipo == 'Saída' ? 'Para onde foi' : 'De onde veio';

  @override
  void initState() {
    super.initState();
    for (final m in widget.movimentos ?? const []) {
      _movimentos.add(Map<String, dynamic>.from(m));
    }
  }

  @override
  void dispose() {
    _localController.dispose();
    _localFoco.dispose();
    _produtosController.dispose();
    _produtosFoco.dispose();
    _rolagem.dispose();
    super.dispose();
  }

  void _limpar() {
    _tipo = null;
    _localController.clear();
    _produtosController.clear();
  }

  /// "Confirmar" (ou "Confirmar Edição"): guarda o lançamento na lista (ou
  /// grava o editado) e limpa os campos.
  Future<void> _confirmar() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final erro = _tipo == null
        ? 'Marque se é Chegada ou Saída.'
        : _localController.text.trim().isEmpty
        ? 'Informe ${_tipo == 'Saída' ? 'para onde foi' : 'de onde veio'}.'
        : _produtosController.text.trim().isEmpty
        ? 'Informe os Produtos e Quantidades.'
        : null;
    if (erro != null) {
      await AppAlert.erro(context, erro);
      return;
    }
    setState(() {
      final movimento = <String, dynamic>{
        'tipo': _tipo,
        'local': _localController.text.trim(),
        'produtos': _produtosController.text.trim(),
      };
      if (_editando != null) {
        _movimentos[_editando!] = movimento;
        _editando = null;
      } else {
        _movimentos.add(movimento);
      }
      _limpar();
    });
  }

  /// Editar um lançamento da lista: os dados dele voltam para os campos.
  void _editar(int n) {
    FocusManager.instance.primaryFocus?.unfocus();
    final m = _movimentos[n];
    setState(() {
      _editando = n;
      _limpar();
      _tipo = m['tipo']?.toString();
      _localController.text = '${m['local'] ?? ''}';
      _produtosController.text = '${m['produtos'] ?? ''}';
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
      _limpar();
    });
  }

  /// Nome do lançamento na lista: "Chegada N" / "Saída N", numerado dentro
  /// de cada opção.
  String _nome(int n) {
    final tipo = '${_movimentos[n]['tipo'] ?? ''}';
    var numero = 0;
    for (var i = 0; i <= n; i++) {
      if (_movimentos[i]['tipo'] == tipo) numero++;
    }
    return '$tipo $numero';
  }

  /// Excluir um lançamento da lista (pergunta antes).
  Future<void> _excluir(int n) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final nome = _nome(n);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Excluir ${_movimentos[n]['tipo']}',
          style: const TextStyle(fontSize: 17, color: _azulTitulo),
        ),
        content: Text('Excluir a $nome?'),
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
      if (_editando == n) {
        _editando = null;
        _limpar();
      }
      _movimentos.removeAt(n);
      if (_editando != null && _editando! > n) _editando = _editando! - 1;
    });
  }

  /// Chegada / Saída (uma só) lado a lado, no padrão dos botões do Serviço,
  /// com o check verde no marcado — sem efeito de toque.
  Widget _opcoesTipo() {
    const azulIcone = Color(0xFF228cb9);
    return Row(
      children: [
        for (var i = 0; i < _opcoes.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() => _tipo = _opcoes[i].$1);
              },
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _tipo == _opcoes[i].$1
                      ? const Color(0xFFCFE5FA)
                      : const Color(0xFFF9FCFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(_opcoes[i].$2, size: 22, color: azulIcone),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _opcoes[i].$1,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'FuturaStdMedium',
                          fontSize: 14,
                          color: _corRotulo,
                        ),
                      ),
                    ),
                    if (_tipo == _opcoes[i].$1)
                      Icon(Icons.check, color: Colors.green[600], size: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
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

  /// Lista dos lançamentos, com rolagem, do último para o primeiro:
  /// "Chegada N" / "Saída N", de onde veio / para onde foi, os produtos e
  /// os ícones de editar e excluir.
  Widget _listaMovimentos() {
    final estilo = TextStyle(fontSize: 11, color: _corRotulo);
    final linhas = <TableRow>[];
    for (var n = _movimentos.length - 1; n >= 0; n--) {
      final m = _movimentos[n];
      final topo = linhas.isNotEmpty ? 8.0 : 2.0;
      linhas.add(
        TableRow(
          // o lançamento em edição fica em azul claro
          decoration: n == _editando
              ? const BoxDecoration(color: Color(0xFFD6E8FA))
              : null,
          children: [
            Padding(
              padding: EdgeInsets.only(top: topo, right: 8),
              child: Text(_nome(n), style: estilo),
            ),
            Padding(
              padding: EdgeInsets.only(top: topo, right: 6),
              child: Text('${m['local'] ?? ''}', style: estilo),
            ),
            Padding(
              padding: EdgeInsets.only(top: topo, right: 4),
              child: Text('${m['produtos'] ?? ''}', style: estilo),
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
            // local e produtos dividem o que sobrar (quebram se precisar)
            columnWidths: const {1: FlexColumnWidth(), 2: FlexColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: linhas,
          ),
        ),
      ),
    );
  }

  /// Botão do modal (Confirmar / Confirmar Edição / Cancelar).
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
      // centralizado, mas sem passar para cima da barra do título "Resumo
      // Diário da Fazenda" quando o conteúdo é alto
      alignment: Alignment.center,
      insetPadding: const EdgeInsets.fromLTRB(16, 72, 16, 24),
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
                        ? 'Chegada / Saída'
                        : '${_nome(_editando!)} — editando',
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
                        _opcoesTipo(),
                        // "De onde veio" (Chegada) / "Para onde foi" (Saída)
                        if (_tipo != null) ...[
                          const SizedBox(height: 12),
                          CampoTextoTopo(
                            rotulo: _rotuloLocal,
                            corRotulo: _corRotulo,
                            controller: _localController,
                            focusNode: _localFoco,
                            textCapitalization: TextCapitalization.sentences,
                          ),
                        ],
                        const SizedBox(height: 12),
                        CampoTextoTopo(
                          rotulo: 'Produtos e Quantidades',
                          corRotulo: _corRotulo,
                          controller: _produtosController,
                          focusNode: _produtosFoco,
                          altura: null,
                          linhas: 3,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 14),
                        if (_editando == null)
                          _botao('Confirmar', _confirmar)
                        else
                          Row(
                            children: [
                              Expanded(
                                child: _botao(
                                  'Confirmar Edição',
                                  _confirmar,
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
                        if (_movimentos.isNotEmpty) _listaMovimentos(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // (x) no canto: fecha; os lançamentos da lista valem do jeito que
          // estão (só o que está nos campos e não foi confirmado se perde)
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
                  'movimentos': _movimentos,
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
