import 'package:flutter/material.dart';

import '../utils/app_alert.dart';
import '../utils/rolar_ate_foco.dart';
import '../widgets/campo_topo_widget.dart';

/// Modal "Pedido" do Resumo Diário (Seção 7 — Solicitação de Produtos, card
/// "Adicionar Produtos"). Mesmo visual e funcionamento dos modais das Seções
/// 5 e 6: fundo cinza, (x) no canto, conteúdo com rolagem, botão verde que
/// guarda o pedido na lista de baixo (editar e excluir, o último no topo).
///
/// Campos: Tipo (um só), Descrição e Quantidade, os dois com exemplos de
/// acordo com o tipo. Devolve { pedidos } ao fechar pelo (x).
class PedidoModal extends StatefulWidget {
  /// Pedidos já incluídos (editar); null = nenhum.
  final List<Map<String, dynamic>>? pedidos;

  const PedidoModal({super.key, this.pedidos});

  @override
  State<PedidoModal> createState() => _PedidoModalState();
}

class _PedidoModalState extends State<PedidoModal> {
  static const _azulTitulo = Color(0xFF18385F);
  static const _azulBotao = Color(0xFF007AFF);
  static const _verde = Color(0xFF4CAF50);
  static final _corRotulo = Colors.blueGrey[800]!;

  /// Tipos do pedido com os exemplos da Descrição e da Quantidade.
  static const _tipos = <(String, String, String)>[
    (
      'Produto veterinário',
      'Ex: Ivermectina, Antibiótico, Vermífugo',
      'Ex: 5 frascos, 2 caixas',
    ),
    ('Nutrição', 'Ex: Sal mineral, Ureia, Fubá, Soja', 'Ex: 10 sacos de 30 kg'),
    (
      'Materiais',
      'Ex: Arame, Mourão, Cimento, Pregos',
      'Ex: 5 rolos, 20 unidades',
    ),
    (
      'Equip / máquina / peça',
      'Ex: Bomba, Roçadeira, Peça de reposição',
      'Ex: 1 unidade',
    ),
    (
      'Combustível / Óleo',
      'Ex: Diesel S10, Óleo hidráulico, Graxa',
      'Ex: 200 litros, 5 galões',
    ),
    (
      'Serviço externo',
      'Ex: Conserto de..., Veterinário, Mecânico',
      'Ex: 1 visita',
    ),
    ('Outro', 'Ex: Descreva o que precisa', 'Ex: 1 unidade'),
  ];

  /// Urgência do pedido (uma, obrigatório) e a cor da bolinha.
  static const _urgencias = <(String, Color?)>[
    ('Até amanhã', Color(0xFFE53935)),
    ('Semana que vem', Color(0xFFFDD835)),
    ('Manutenção de estoque', Color(0xFF43A047)),
    ('Outro', null),
  ];

  /// Cor da bolinha da urgência (null = branca, só o contorno).
  static Color? _corUrgencia(String? urgencia) {
    for (final u in _urgencias) {
      if (u.$1 == urgencia) return u.$2;
    }
    return null;
  }

  String? _tipo;
  bool _tipoAberto = false;
  String? _urgencia;

  /// Urgência "Outro": descrição obrigatória.
  final _urgenciaOutroController = TextEditingController();
  final _urgenciaOutroFoco = FocusNode();
  final _descricaoController = TextEditingController();
  final _descricaoFoco = FocusNode();
  final _qtdeController = TextEditingController();
  final _qtdeFoco = FocusNode();

  /// Pedidos já confirmados, na ordem em que foram incluídos.
  final List<Map<String, dynamic>> _pedidos = [];

  /// Pedido da lista em edição (índice em [_pedidos]); null = novo.
  int? _editando;

  final _rolagem = ScrollController();

  /// Exemplos (Descrição, Quantidade) do tipo escolhido.
  (String, String) get _exemplos {
    for (final t in _tipos) {
      if (t.$1 == _tipo) return (t.$2, t.$3);
    }
    return ('', '');
  }

  @override
  void initState() {
    super.initState();
    for (final p in widget.pedidos ?? const []) {
      _pedidos.add(Map<String, dynamic>.from(p));
    }
    // foi para a Descrição ou a Quantidade: fecha a lista do Tipo
    void fecharTipo() {
      if (_tipoAberto && (_descricaoFoco.hasFocus || _qtdeFoco.hasFocus)) {
        setState(() => _tipoAberto = false);
      }
    }

    _descricaoFoco.addListener(fecharTipo);
    _qtdeFoco.addListener(fecharTipo);
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    _descricaoFoco.dispose();
    _qtdeController.dispose();
    _qtdeFoco.dispose();
    _rolagem.dispose();
    super.dispose();
  }

  void _limpar() {
    _tipo = null;
    _tipoAberto = false;
    _descricaoController.clear();
    _qtdeController.clear();
    _urgencia = null;
  }

  /// "Confirmar Pedido" (ou "Confirmar Edição"): guarda o pedido na lista
  /// (ou grava o editado) e limpa os campos.
  Future<void> _confirmar() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final erro = _tipo == null
        ? 'Selecione o Tipo.'
        : _descricaoController.text.trim().isEmpty
        ? 'Informe a Descrição.'
        : _qtdeController.text.trim().isEmpty
        ? 'Informe a Quantidade.'
        : _urgencia == null
        ? 'Selecione a Urgência.'
        : null;
    if (erro != null) {
      await AppAlert.erro(context, erro);
      return;
    }
    setState(() {
      final pedido = <String, dynamic>{
        'tipo': _tipo,
        'descricao': _descricaoController.text.trim(),
        'quantidade': _qtdeController.text.trim(),
        'urgencia': _urgencia,
      };
      if (_editando != null) {
        _pedidos[_editando!] = pedido;
        _editando = null;
      } else {
        _pedidos.add(pedido);
      }
      _limpar();
    });
  }

  /// Editar um pedido da lista: os dados dele voltam para os campos.
  void _editar(int n) {
    FocusManager.instance.primaryFocus?.unfocus();
    final p = _pedidos[n];
    setState(() {
      _editando = n;
      _limpar();
      _tipo = p['tipo']?.toString();
      _descricaoController.text = '${p['descricao'] ?? ''}';
      _qtdeController.text = '${p['quantidade'] ?? ''}';
      _urgencia = p['urgencia']?.toString();
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

  /// Excluir um pedido da lista (pergunta antes).
  Future<void> _excluir(int n) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Excluir Pedido',
          style: TextStyle(fontSize: 17, color: _azulTitulo),
        ),
        content: Text('Excluir o Pedido ${n + 1}?'),
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
      _pedidos.removeAt(n);
      if (_editando != null && _editando! > n) _editando = _editando! - 1;
    });
  }

  /// Select "Tipo" (um só) com a lista aberta embaixo do próprio campo: um
  /// toque escolhe e fecha.
  Widget _selectTipo() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CampoValorTopo(
        rotulo: 'Tipo',
        corRotulo: _corRotulo,
        valor: _tipo ?? '',
        icone: Icon(
          _tipoAberto ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          color: _corRotulo,
        ),
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() => _tipoAberto = !_tipoAberto);
        },
      ),
      if (_tipoAberto)
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
              for (final t in _tipos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Material(
                    color: t.$1 == _tipo
                        ? const Color(0xFFD6E8FA)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() {
                        _tipo = t.$1;
                        _tipoAberto = false;
                      }),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.$1,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: t.$1 == _tipo
                                      ? _azulTitulo
                                      : Colors.black87,
                                ),
                              ),
                            ),
                            if (t.$1 == _tipo)
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
    ],
  );

  /// Bolinha da urgência com contorno escuro (sem cor = branca).
  Widget _bolinha(Color? cor, double tamanho) => Container(
    width: tamanho,
    height: tamanho,
    decoration: BoxDecoration(
      color: cor ?? Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.black87, width: 1),
    ),
  );

  /// Urgência (uma só) em 2 x 2: bolinha colorida e o texto, no mesmo padrão
  /// dos botões de andamento do Serviço — sem efeito de toque.
  Widget _opcoesUrgencia() {
    Widget opcao((String, Color?) u) => Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() {
            _urgencia = u.$1;
            _tipoAberto = false;
          });
        },
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: _urgencia == u.$1
                ? const Color(0xFFCFE5FA)
                : const Color(0xFFF9FCFF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _bolinha(u.$2, 14),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  u.$1,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontFamily: 'FuturaStdMedium',
                    fontSize: 13,
                    color: _corRotulo,
                    shadows: [
                      Shadow(color: _corRotulo, offset: const Offset(0.4, 0)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            'Urgência',
            style: TextStyle(fontSize: 14, color: _corRotulo),
          ),
        ),
        Row(
          children: [
            opcao(_urgencias[0]),
            const SizedBox(width: 8),
            opcao(_urgencias[1]),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            opcao(_urgencias[2]),
            const SizedBox(width: 8),
            opcao(_urgencias[3]),
          ],
        ),
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

  /// Lista dos pedidos, com rolagem, do último para o primeiro: "Pedido N",
  /// a descrição, a quantidade e os ícones de editar e excluir.
  Widget _listaPedidos() {
    final estilo = TextStyle(fontSize: 11, color: _corRotulo);
    final linhas = <TableRow>[];
    for (var n = _pedidos.length - 1; n >= 0; n--) {
      final p = _pedidos[n];
      final topo = linhas.isNotEmpty ? 8.0 : 2.0;
      linhas.add(
        TableRow(
          // o pedido em edição fica em azul claro
          decoration: n == _editando
              ? const BoxDecoration(color: Color(0xFFD6E8FA))
              : null,
          children: [
            Padding(
              padding: EdgeInsets.only(top: topo, right: 8),
              // bolinha com a cor da urgência na frente do "Pedido N"
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _bolinha(_corUrgencia(p['urgencia']?.toString()), 9),
                  const SizedBox(width: 5),
                  Text('Pedido ${n + 1}', style: estilo),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: topo, right: 6),
              child: Text('${p['descricao'] ?? ''}', style: estilo),
            ),
            Padding(
              padding: EdgeInsets.only(top: topo, right: 4),
              child: Text('${p['quantidade'] ?? ''}', style: estilo),
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
            // a descrição fica com o que sobrar (quebra se precisar)
            columnWidths: const {1: FlexColumnWidth()},
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
    final exemplos = _exemplos;
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
                        ? 'Pedido'
                        : 'Pedido ${_editando! + 1} — editando',
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
                        _selectTipo(),
                        const SizedBox(height: 12),
                        // exemplos de acordo com o tipo escolhido
                        CampoTextoTopo(
                          rotulo: 'Descrição',
                          corRotulo: _corRotulo,
                          controller: _descricaoController,
                          focusNode: _descricaoFoco,
                          dica: exemplos.$1.isEmpty ? null : exemplos.$1,
                          altura: null,
                          linhas: 2,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 12),
                        CampoTextoTopo(
                          rotulo: 'Quantidade',
                          corRotulo: _corRotulo,
                          controller: _qtdeController,
                          focusNode: _qtdeFoco,
                          dica: exemplos.$2.isEmpty ? null : exemplos.$2,
                          altura: 64,
                        ),
                        const SizedBox(height: 12),
                        _opcoesUrgencia(),
                        const SizedBox(height: 14),
                        if (_editando == null)
                          _botao('Confirmar Pedido', _confirmar)
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
                        if (_pedidos.isNotEmpty) _listaPedidos(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // (x) no canto: fecha; os pedidos da lista valem do jeito que estão
          // (só o que está nos campos e não foi confirmado se perde)
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
                  'pedidos': _pedidos,
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
