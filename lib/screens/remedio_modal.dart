import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_alert.dart';
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
  final _rolagem = ScrollController();

  @override
  void initState() {
    super.initState();
    final d = widget.dados;
    if (d != null) {
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

  Future<void> _confirmar() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final erro = _categoria == null
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
    if (erro != null) {
      await AppAlert.erro(context, erro);
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, <String, dynamic>{
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

  /// Rótulo do campo em negrito (a fonte do app só tem a versão fina: o
  /// traço é engrossado com "sombras" da mesma cor).
  Widget _rotulo(String texto) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 2),
    child: Text(
      texto,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w900,
        color: _corRotulo,
        shadows: [
          Shadow(color: _corRotulo, offset: const Offset(0.4, 0)),
          Shadow(color: _corRotulo, offset: const Offset(-0.4, 0)),
        ],
      ),
    ),
  );

  /// Lista já aberta, como a do Tratamento, mas de uma opção só: um toque
  /// escolhe a categoria (a anterior sai); embaixo, a escolhida.
  List<Widget> _listaCategoria() => [
    _rotulo('Categoria Animal'),
    Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 4),
      child: Text(
        'Toque para selecionar uma opção.',
        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
      ),
    ),
    Container(
      // 4 linhas à vista; o resto rola
      height: 4 * 44 + 8,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Scrollbar(
        thumbVisibility: true,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          itemExtent: 44,
          itemCount: _categorias.length,
          itemBuilder: (context, i) {
            final c = _categorias[i];
            final marcado = c == _categoria;
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Material(
                color: marcado ? const Color(0xFFD6E8FA) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() => _categoria = c);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            c,
                            style: TextStyle(
                              fontSize: 14,
                              color: marcado ? _azulTitulo : Colors.black87,
                            ),
                          ),
                        ),
                        if (marcado)
                          const Icon(Icons.check, size: 18, color: _azulBotao),
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
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Text(
        _categoria ?? 'Nenhuma selecionada',
        // só uma referência do que foi escolhido: pequena e em azul claro
        style: TextStyle(
          fontSize: 11,
          fontStyle: FontStyle.italic,
          color: _categoria == null ? Colors.grey[600] : Colors.blue[300],
        ),
      ),
    ),
  ];

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
    final varios = marcados != null;
    final escolhidos = [
      for (final o in opcoes)
        if (varios ? marcados.contains(o) : o == valor) o,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampoValorTopo(
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
            setState(() => _selectAberto = aberto ? null : rotulo);
          },
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
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Colors.blue[300],
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
                        ..._listaCategoria(),
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
                        const SizedBox(height: 12),
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
                        'Confirmar Aplicação',
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
