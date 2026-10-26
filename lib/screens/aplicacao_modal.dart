import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_alert.dart';
import '../widgets/campo_topo_widget.dart';

/// Modal "Aplicação N" do Resumo Diário (Seção 4 — Vacinas, Vermífugos e
/// Carrapaticidas). Mesmo padrão do modal do Tratamento: fundo cinza, (x)
/// no canto para fechar sem criar nada, conteúdo com rolagem e o botão
/// "Confirmar Aplicação".
///
/// Devolve os dados da aplicação ao confirmar; null ao fechar pelo (x).
class AplicacaoModal extends StatefulWidget {
  /// Número da aplicação (1, 2, 3...).
  final int numero;

  /// Dados de uma aplicação já incluída (editar); null = nova.
  final Map<String, dynamic>? dados;

  const AplicacaoModal({super.key, required this.numero, this.dados});

  @override
  State<AplicacaoModal> createState() => _AplicacaoModalState();
}

class _AplicacaoModalState extends State<AplicacaoModal> {
  static const _azulTitulo = Color(0xFF18385F);
  static const _azulBotao = Color(0xFF007AFF);
  static const _verde = Color(0xFF4CAF50);
  static final _corRotulo = Colors.blueGrey[800]!;

  static const _tipos = ['Vacina', 'Vermífugo', 'Carrapaticida'];

  /// Produtos por tipo (os de Vermífugo e Carrapaticida ainda não foram
  /// definidos).
  static const _produtosPorTipo = <String, List<String>>{
    'Vacina': ['Raiva', 'Mal de Ano', 'Brucelose', 'Aftosa', 'Pneumonia'],
    'Vermífugo': [],
    'Carrapaticida': [],
  };

  static const _categorias = [
    'Bezerros 0–7m',
    'Bezerros 8–12m',
    'Novilhas 13–24m',
    'Garrotes 13–24m',
    'Vacas',
    'Bois',
    'CAVALOS',
  ];

  static const _unidades = ['ml', 'ml/kg'];

  String _tipo = 'Vacina';
  String? _produto;
  String? _categoria;
  String? _unidade;
  final _qtdeController = TextEditingController();
  final _volumeController = TextEditingController();

  /// Select aberto embaixo do campo (só um por vez): 'tipo', 'produto',
  /// 'categoria' ou 'unidade'.
  String? _aberto;
  final _listaAberta = GlobalKey();

  @override
  void initState() {
    super.initState();
    final d = widget.dados;
    if (d != null) {
      _tipo = (d['tipo'] ?? 'Vacina').toString();
      _produto = d['produto']?.toString();
      _categoria = d['categoria']?.toString();
      _unidade = d['unidade']?.toString();
      _qtdeController.text = (d['qtde'] ?? '').toString();
      _volumeController.text = (d['volume'] ?? '').toString();
    }
  }

  @override
  void dispose() {
    _qtdeController.dispose();
    _volumeController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final qtde = int.tryParse(_qtdeController.text.trim()) ?? 0;
    final volume = int.tryParse(_volumeController.text.trim()) ?? 0;
    final erro = _produto == null
        ? 'Selecione o Nome do Produto.'
        : qtde <= 0
        ? 'Informe a Quantidade de Animais por Categoria.'
        : _categoria == null
        ? 'Selecione a Categoria Animal.'
        : volume <= 0
        ? 'Informe o Volume da dose aplicada.'
        : _unidade == null
        ? 'Selecione a Unidade da dose aplicada.'
        : null;
    if (erro != null) {
      await AppAlert.erro(context, erro);
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, <String, dynamic>{
      'tipo': _tipo,
      'produto': _produto,
      'qtde': qtde,
      'categoria': _categoria,
      'volume': volume,
      'unidade': _unidade,
    });
  }

  /// Rótulo em negrito (a fonte do app só tem a versão fina: o traço é
  /// engrossado com "sombras" da mesma cor).
  Widget _rotulo(String texto) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 6),
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

  /// Abre (ou fecha) a lista do select embaixo do campo e rola o modal até
  /// ela ficar à vista.
  Future<void> _abrir(String chave, List<String> opcoes) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (opcoes.isEmpty) {
      await AppAlert.erro(
        context,
        'Os produtos de $_tipo ainda não foram cadastrados.',
      );
      return;
    }
    setState(() => _aberto = _aberto == chave ? null : chave);
    if (_aberto == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _listaAberta.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  /// Select de uma opção só (como o Responsável do Tratamento): o campo
  /// fechado e, ao tocar, a lista abre embaixo dele dentro do modal; um
  /// toque escolhe e fecha.
  List<Widget> _select(
    String chave,
    String rotulo,
    String? valor,
    List<String> opcoes,
    ValueChanged<String> aoEscolher,
  ) {
    final aberto = _aberto == chave;
    return [
      CampoValorTopo(
        rotulo: rotulo,
        corRotulo: _corRotulo,
        valor: valor ?? '',
        icone: Icon(
          aberto ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          color: _corRotulo,
        ),
        onTap: () => _abrir(chave, opcoes),
      ),
      if (aberto)
        Container(
          key: _listaAberta,
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 4 * 44 + 8),
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
              itemCount: opcoes.length,
              itemBuilder: (context, i) {
                final o = opcoes[i];
                final marcado = o == valor;
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
                        aoEscolher(o);
                        _aberto = null;
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                o,
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
    ];
  }

  @override
  Widget build(BuildContext context) {
    // teclado aberto: o "Confirmar Aplicação" some para o campo em edição
    // ficar à vista (como no modal do Tratamento)
    final tecladoAberto = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Dialog(
      backgroundColor: Colors.transparent,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 44, 6),
                  child: Text(
                    'Aplicação ${widget.numero}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, color: _azulTitulo),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ..._select('tipo', 'Tipo', _tipo, _tipos, (v) {
                          // outro tipo: o produto escolhido deixa de valer
                          if (v != _tipo) _produto = null;
                          _tipo = v;
                        }),
                        const SizedBox(height: 8),
                        ..._select(
                          'produto',
                          'Nome do Produto',
                          _produto,
                          _produtosPorTipo[_tipo] ?? const [],
                          (v) => _produto = v,
                        ),
                        const SizedBox(height: 8),
                        CampoTextoTopo(
                          rotulo: 'Quantidade de Animais por Categoria',
                          corRotulo: _corRotulo,
                          controller: _qtdeController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                        const SizedBox(height: 8),
                        ..._select(
                          'categoria',
                          'Categoria Animal',
                          _categoria,
                          _categorias,
                          (v) => _categoria = v,
                        ),
                        const SizedBox(height: 12),
                        _rotulo('Dose Aplicada'),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: CampoTextoTopo(
                                rotulo: 'Volume',
                                corRotulo: _corRotulo,
                                controller: _volumeController,
                                dica: 'Ex: 5',
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _select(
                                  'unidade',
                                  'Unidade',
                                  _unidade,
                                  _unidades,
                                  (v) => _unidade = v,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (tecladoAberto)
                  const SizedBox(height: 8)
                else
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
          // (x) no canto: fecha sem criar nada
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
