import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/resumo_diario_service.dart';
import '../utils/app_alert.dart';
import '../utils/rolar_ate_foco.dart';
import '../widgets/campo_topo_widget.dart';

/// Modal "Tratamento N" do Resumo Diário (Seção 3 — Sanidade Animal).
/// Fundo cinza no padrão dos outros modais, (x) no canto para fechar sem
/// criar nada, conteúdo com rolagem e o botão "Confirmar Tratamento".
///
/// Devolve os dados do tratamento ao confirmar; null ao fechar pelo (x).
class TratamentoModal extends StatefulWidget {
  /// Número do tratamento (1, 2, 3...).
  final int numero;

  /// Dados de um tratamento já incluído (editar); null = novo.
  final Map<String, dynamic>? dados;

  /// Empresa (CNPJ) e fazenda do resumo: carregam o select Responsável.
  final String bd;
  final String fazenda;

  const TratamentoModal({
    super.key,
    required this.numero,
    this.dados,
    required this.bd,
    required this.fazenda,
  });

  @override
  State<TratamentoModal> createState() => _TratamentoModalState();
}

class _TratamentoModalState extends State<TratamentoModal> {
  static const _azulTitulo = Color(0xFF18385F);
  static const _azulBotao = Color(0xFF007AFF);
  static const _verde = Color(0xFF4CAF50);
  static final _corRotulo = Colors.blueGrey[800]!;

  static const _categorias = [
    'Bezerros 0–7m',
    'Bezerros 8–12m',
    'Novilhas 13–24m',
    'Garrotes 13–24m',
    'Vacas',
    'Bois',
    'CAVALOS',
  ];

  static const _sintomasOpcoes = [
    'Apático',
    'Bicheira',
    'Diarreia',
    'Mancando',
    'Coriza / Tosse',
    'Outro',
  ];

  final Set<String> _categoriasMarcadas = {};
  final Set<String> _sintomasMarcados = {};
  final _qtdeController = TextEditingController();
  final _brincoController = TextEditingController();
  final _tratamentoController = TextEditingController();
  String? _responsavel;

  /// Lista do Responsável aberta embaixo do campo.
  bool _responsavelAberto = false;
  final _rolagem = ScrollController();
  List<MapEntry<String, String>> _responsaveis = [];

  @override
  void initState() {
    super.initState();
    final d = widget.dados;
    if (d != null) {
      _categoriasMarcadas.addAll(List<String>.from(d['categorias'] ?? []));
      _sintomasMarcados.addAll(List<String>.from(d['sintomas'] ?? []));
      _qtdeController.text = (d['qtde'] ?? '').toString();
      _brincoController.text = (d['brinco'] ?? '').toString();
      _tratamentoController.text = (d['tratamento'] ?? '').toString();
      _responsavel = d['responsavel_id']?.toString();
    }
    _carregarResponsaveis();
  }

  Future<void> _carregarResponsaveis() async {
    final lista = await ResumoDiarioService.instance.responsaveis(
      widget.bd,
      widget.fazenda,
    );
    if (!mounted) return;
    setState(() => _responsaveis = lista);
  }

  @override
  void dispose() {
    _qtdeController.dispose();
    _brincoController.dispose();
    _tratamentoController.dispose();
    _rolagem.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final qtde = int.tryParse(_qtdeController.text.trim()) ?? 0;
    final erro = _categoriasMarcadas.isEmpty
        ? 'Selecione a Categoria Animal.'
        : qtde <= 0
        ? 'Informe a Qtde Animais.'
        : _sintomasMarcados.isEmpty
        ? 'Selecione os Sintomas.'
        : _tratamentoController.text.trim().isEmpty
        ? 'Informe o Tratamento Aplicado.'
        : _responsavel == null
        ? 'Selecione o Responsável.'
        : null;
    if (erro != null) {
      await AppAlert.erro(context, erro);
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, <String, dynamic>{
      // na ordem das opções, não na ordem em que foram tocadas
      'categorias': [
        for (final c in _categorias)
          if (_categoriasMarcadas.contains(c)) c,
      ],
      'qtde': qtde,
      'brinco': _brincoController.text.trim(),
      'sintomas': [
        for (final s in _sintomasOpcoes)
          if (_sintomasMarcados.contains(s)) s,
      ],
      'tratamento': _tratamentoController.text.trim(),
      'responsavel_id': _responsavel,
      'responsavel_nome': _responsaveis
          .where((r) => r.key == _responsavel)
          .map((r) => r.value)
          .firstOrNull,
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

  /// Lista já aberta (como o select múltiplo do web): um toque marca ou
  /// desmarca a linha (fica destacada, com o ✓, igual ao select de pastos
  /// da Seção 2); embaixo, os nomes marcados.
  List<Widget> _listaMultipla(
    String titulo,
    List<String> opcoes,
    Set<String> marcados,
  ) => [
    _rotulo(titulo),
    Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 4),
      child: Text(
        'Toque para selecionar uma ou mais opções.',
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
          itemCount: opcoes.length,
          itemBuilder: (context, i) {
            final o = opcoes[i];
            final marcado = marcados.contains(o);
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Material(
                color: marcado ? const Color(0xFFD6E8FA) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() {
                      if (marcado) {
                        marcados.remove(o);
                      } else {
                        marcados.add(o);
                      }
                    });
                  },
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
        marcados.isEmpty
            ? 'Nenhum selecionado'
            : [
                for (final o in opcoes)
                  if (marcados.contains(o)) o,
              ].join(', '),
        style: TextStyle(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: marcados.isEmpty ? Colors.grey[600] : _corRotulo,
        ),
      ),
    ),
  ];

  /// Select Responsável: abre (ou fecha) a lista embaixo do campo, dentro
  /// do modal, que rola até ela.
  Future<void> _abrirResponsavel() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_responsaveis.isEmpty) {
      await AppAlert.erro(
        context,
        'A lista de responsáveis ainda não foi baixada neste aparelho. '
        'Abra o tratamento com internet e tente de novo.',
      );
      return;
    }
    setState(() => _responsavelAberto = !_responsavelAberto);
    if (!_responsavelAberto) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_rolagem.hasClients) return;
      _rolagem.animateTo(
        _rolagem.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// Lista do Responsável (uma opção só): um toque escolhe e fecha.
  Widget _listaResponsavel() => Container(
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
        itemCount: _responsaveis.length,
        itemBuilder: (context, i) {
          final r = _responsaveis[i];
          final marcado = r.key == _responsavel;
          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Material(
              color: marcado ? const Color(0xFFD6E8FA) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() {
                  _responsavel = r.key;
                  _responsavelAberto = false;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.value,
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
  );

  Widget _campoResponsavel() => CampoValorTopo(
    rotulo: 'Responsável',
    corRotulo: _corRotulo,
    valor:
        _responsaveis
            .where((r) => r.key == _responsavel)
            .map((r) => r.value)
            .firstOrNull ??
        '',
    icone: Icon(
      _responsavelAberto ? Icons.arrow_drop_up : Icons.arrow_drop_down,
      color: _corRotulo,
    ),
    onTap: _abrirResponsavel,
  );

  bool _tecladoAntes = false;

  @override
  Widget build(BuildContext context) {
    // teclado aberto: o "Confirmar Tratamento" some para o campo em edição
    // ficar à vista (como a barra Anterior/Próximo da tela do resumo)
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 44, 6),
                  child: Text(
                    'Tratamento ${widget.numero}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, color: _azulTitulo),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    controller: _rolagem,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ..._listaMultipla(
                          'Categoria Animal',
                          _categorias,
                          _categoriasMarcadas,
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
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: CampoTextoTopo(
                                rotulo: 'Id do Brinco',
                                rotuloComplemento: '(opcional)',
                                corRotulo: _corRotulo,
                                controller: _brincoController,
                                textCapitalization:
                                    TextCapitalization.characters,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._listaMultipla(
                          'Sintomas',
                          _sintomasOpcoes,
                          _sintomasMarcados,
                        ),
                        const SizedBox(height: 12),
                        CampoTextoTopo(
                          rotulo: 'Tratamento Aplicado',
                          corRotulo: _corRotulo,
                          controller: _tratamentoController,
                          dica: 'Ex: Pomada cicatrizante',
                          // mais alto: várias linhas
                          altura: null,
                          linhas: 3,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 8),
                        _campoResponsavel(),
                        if (_responsavelAberto) _listaResponsavel(),
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
                          'Confirmar Tratamento',
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
