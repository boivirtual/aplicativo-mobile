import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/daos/mapa_gado_dao.dart';
import '../utils/app_alert.dart';
import '../widgets/campo_topo_widget.dart';
import '../widgets/indicador_conectividade_widget.dart';
import '../widgets/seletor_campo_widget.dart';

/// "Resumo Diário da Fazenda": conferência, por usuário logado, dos
/// serviços feitos na fazenda no dia. São 10 seções, mostradas uma de cada
/// vez; o usuário só avança (Próximo) depois de preencher a seção atual.
///
/// Por enquanto só a Seção 1 (Identificação): data (hoje, pode ser anterior,
/// nunca futura), fazenda (as do usuário; uma só já vem escolhida) e o
/// responsável (o usuário logado, sem digitar). O Próximo ainda não avança.
class ResumoDiarioScreen extends StatefulWidget {
  const ResumoDiarioScreen({super.key});

  @override
  State<ResumoDiarioScreen> createState() => _ResumoDiarioScreenState();
}

class _ResumoDiarioScreenState extends State<ResumoDiarioScreen> {
  static const _azul = Color(0xFF18385F);
  static const _azulBotao = Color(0xFF007AFF);
  static final _corRotulo = Colors.blueGrey[800]!;

  static const _totalSecoes = 10;
  int _secao = 1;

  // Seção 2 — Conferência de Rebanho
  String? _conferiuGado; // 'todo', 'parte', 'nao'
  final _esperadosController = TextEditingController();
  final _encontradosController = TextEditingController();
  String? _conferiuPrenhas; // 'sim', 'nao', 'sem'
  final _obsRebanhoController = TextEditingController();
  // pastos onde está a diferença (quando Esperados ≠ Encontrados)
  final Set<int> _pastosDiferenca = {};
  List<MapEntry<int, String>> _pastosFazenda = [];
  String? _pastosDaFazenda; // fazenda dos pastos carregados

  int? get _esperados => int.tryParse(_esperadosController.text.trim());
  int? get _encontrados => int.tryParse(_encontradosController.text.trim());

  /// Encontrados − Esperados (null enquanto falta um dos dois).
  int? get _diferenca {
    final e = _esperados, n = _encontrados;
    return e == null || n == null ? null : n - e;
  }

  /// Pastos da fazenda escolhida (do mapa guardado no aparelho).
  Future<void> _carregarPastos() async {
    final fazenda = _fazenda;
    final bd = _bd;
    if (fazenda == null || bd == null || _pastosDaFazenda == fazenda) return;
    final pastos = await MapaGadoDao.instance.pastos(
      bd,
      int.tryParse(fazenda) ?? 0,
      incluirForaTabuleiro: true,
    );
    if (!mounted) return;
    setState(() {
      _pastosDaFazenda = fazenda;
      _pastosFazenda = [for (final p in pastos) MapEntry(p.id, p.descricao)];
      _pastosDiferenca.removeWhere(
        (id) => !_pastosFazenda.any((p) => p.key == id),
      );
    });
  }

  /// Lista para marcar um ou vários pastos.
  Future<void> _escolherPastos() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _carregarPastos();
    if (!mounted) return;
    if (_pastosFazenda.isEmpty) {
      await AppAlert.erro(
        context,
        'Os pastos desta fazenda ainda não foram baixados neste aparelho. '
        'Abra o Mapa de Gado com internet e tente de novo.',
      );
      return;
    }
    // Como o selectpicker do web: busca no topo e um toque marca/desmarca
    // a linha (fica destacada, com o ✓), sem caixinhas.
    final marcados = {..._pastosDiferenca};
    var busca = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final visiveis = [
            for (final p in _pastosFazenda)
              if (p.value.toUpperCase().contains(busca.toUpperCase())) p,
          ];
          return AlertDialog(
            title: const Text(
              'Em qual(is) pasto(s) está a diferença?',
              style: TextStyle(fontSize: 16, color: _azul),
            ),
            contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    onChanged: (v) => setModal(() => busca = v.trim()),
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Buscar pasto...',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: visiveis.length,
                      itemBuilder: (context, i) {
                        final p = visiveis[i];
                        final marcado = marcados.contains(p.key);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Material(
                            color: marcado
                                ? const Color(0xFFD6E8FA)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => setModal(() {
                                if (marcado) {
                                  marcados.remove(p.key);
                                } else {
                                  marcados.add(p.key);
                                }
                              }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 11,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        p.value,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: marcado
                                              ? _azul
                                              : Colors.black87,
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
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('OK (${marcados.length})'),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true && mounted) {
      setState(
        () => _pastosDiferenca
          ..clear()
          ..addAll(marcados),
      );
    }
  }

  /// Ao digitar os totais: se a diferença sumir (iguais ou incompletos), os
  /// pastos marcados são limpos — numa nova diferença, escolhe-se de novo.
  void _totaisMudaram() {
    setState(() {
      if ((_diferenca ?? 0) == 0) _pastosDiferenca.clear();
    });
  }

  /// Nomes dos pastos marcados, na ordem da lista.
  String get _nomesPastosDiferenca => [
    for (final p in _pastosFazenda)
      if (_pastosDiferenca.contains(p.key)) p.value,
  ].join(', ');

  @override
  void dispose() {
    _esperadosController.dispose();
    _encontradosController.dispose();
    _obsRebanhoController.dispose();
    super.dispose();
  }

  DateTime _data = _hoje();
  List<MapEntry<String, String>> _fazendas = [];
  String? _fazenda;
  String _responsavel = '';
  String? _bd;

  /// "Atividades do Dia" (Seção 1): o que o usuário fez hoje na fazenda.
  /// Muitas estão ligadas aos programas do app (Chuva, Mapa de Gado,
  /// Nascimento, Morte...). "Nenhuma das atividades" exclui as outras.
  static const _nenhuma = 'nenhuma';
  static const _atividades = <(String, String, IconData?, String?)>[
    ('choveu', 'Choveu', null, 'chuva.png'),
    ('mudei_pasto', 'Mudei o gado de pasto', Icons.swap_horiz, null),
    ('nutricao', 'Distribuí nutrição', Icons.grass, null),
    ('nascimento', 'Nascimento', Icons.child_care, null),
    (
      'aborto_natimorto',
      'Aborto / Natimorto',
      Icons.warning_amber_rounded,
      null,
    ),
    ('morte', 'Morreu animal', Icons.heart_broken_outlined, null),
    (_nenhuma, 'Nenhuma das atividades', Icons.block, null),
  ];
  final Set<String> _atividadesMarcadas = {};

  static DateTime _hoje() {
    final a = DateTime.now();
    return DateTime(a.year, a.month, a.day);
  }

  static String _formatar(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final fazendasJson = prefs.getString('userFazendas');
    final lista = fazendasJson == null
        ? const []
        : (json.decode(fazendasJson) as List);
    if (!mounted) return;
    setState(() {
      _responsavel = (prefs.getString('userName') ?? '').toUpperCase();
      _bd = prefs.getString('userCNPJ');
      _fazendas = [
        for (final f in lista)
          MapEntry(
            (f as Map)['id'].toString(),
            f['nome'].toString().toUpperCase(),
          ),
      ];
      // uma fazenda só: já vem escolhida
      if (_fazendas.length == 1) _fazenda = _fazendas.first.key;
    });
  }

  /// Hoje ou uma data anterior; data futura não pode.
  Future<void> _escolherData() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: _hoje(),
      helpText: 'Data do registro',
    );
    if (d != null) setState(() => _data = d);
  }

  /// Só avança com a seção atual preenchida. Os dados de cada seção ficam
  /// guardados ao ir e voltar.
  Future<void> _proximo() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_secao == 2) {
      if (_conferiuGado == null) {
        await AppAlert.erro(context, 'Informe se conferiu o gado.');
        return;
      }
      if (_conferiuGado != 'nao') {
        if (_esperadosController.text.trim().isEmpty ||
            _encontradosController.text.trim().isEmpty) {
          await AppAlert.erro(
            context,
            'Informe o Total de Animais Esperados e o de Encontrados.',
          );
          return;
        }
      }
      final dif = _diferenca;
      if (_conferiuGado != 'nao' &&
          dif != null &&
          dif != 0 &&
          _pastosDiferenca.isEmpty) {
        await AppAlert.erro(
          context,
          'Informe em qual(is) pasto(s) está a diferença.',
        );
        return;
      }
      if (_conferiuPrenhas == null) {
        await AppAlert.erro(context, 'Informe se conferiu as vacas prenhas.');
        return;
      }
      // A Seção 3 vem nas próximas etapas.
      return;
    }
    if (_secao == 1) {
      if (_fazenda == null) {
        await AppAlert.erro(context, 'Selecione a Fazenda.');
        return;
      }
      if (_atividadesMarcadas.isEmpty) {
        await AppAlert.erro(
          context,
          'Marque pelo menos uma das Atividades do Dia (ou "Nenhuma das '
          'atividades").',
        );
        return;
      }
      setState(() => _secao = 2);
    }
  }

  void _anterior() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_secao > 1) setState(() => _secao--);
  }

  void _marcarAtividade(String chave, bool marcada) {
    setState(() {
      if (!marcada) {
        _atividadesMarcadas.remove(chave);
      } else if (chave == _nenhuma) {
        // "Nenhuma" desmarca as outras
        _atividadesMarcadas
          ..clear()
          ..add(_nenhuma);
      } else {
        _atividadesMarcadas
          ..remove(_nenhuma)
          ..add(chave);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Resumo Diário da Fazenda',
          style: TextStyle(fontSize: 18, color: Colors.white),
        ),
        backgroundColor: _azul,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: const [IndicadorConectividadeWidget(), SizedBox(width: 8)],
      ),
      body: Column(
        children: [
          _progresso(),
          // Parte fixa da seção (não rola): na Seção 1, a Identificação e o
          // título das Atividades do Dia.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _fixoDaSecao(),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                // Só esta parte rola (na Seção 1, as Atividades do Dia)
                ListView(
                  // espaço no fim para o último item passar do botão Próximo
                  // (que fica por cima, junto com a barra do celular)
                  padding: EdgeInsets.fromLTRB(
                    12,
                    0,
                    12,
                    MediaQuery.of(context).viewInsets.bottom > 0
                        ? 16
                        : 96 + MediaQuery.of(context).padding.bottom,
                  ),
                  children: _rolavelDaSecao(),
                ),
                // Próximo sempre visível; a tela rola por trás dele. Com o
                // teclado aberto ele sai da frente, para não cobrir o campo
                // que está sendo digitado.
                if (MediaQuery.of(context).viewInsets.bottom == 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      // o fundo branco vai até embaixo (atrás da barra do
                      // celular), para a lista não aparecer ali
                      bottom: false,
                      child: Container(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          10,
                          12,
                          12 + MediaQuery.of(context).padding.bottom,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 6,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Anterior (btn-default) a partir da Seção 2
                            if (_secao > 1) ...[
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE9ECEF),
                                      foregroundColor: const Color(0xFF333333),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: _anterior,
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.arrow_back, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'Anterior',
                                          style: TextStyle(fontSize: 16),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ] else
                              const Spacer(),
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _azulBotao,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: _proximo,
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Próximo',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.arrow_forward, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Barra de progresso (seção atual de 10) e o título da seção.
  Widget _progresso() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF1F3F6),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _secao / _totalSecoes,
              minHeight: 10,
              color: _azulBotao,
              backgroundColor: const Color(0xFFD5DCE4),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Seção $_secao de $_totalSecoes — ${_tituloDaSecao(_secao)}',
            style: const TextStyle(fontSize: 15, color: _azul),
          ),
        ],
      ),
    );
  }

  String _tituloDaSecao(int secao) => switch (secao) {
    1 => 'Identificação/Atividades',
    2 => 'Conferência de Rebanho',
    _ => '',
  };

  List<Widget> _camposDaSecao() => switch (_secao) {
    _ => _secaoIdentificacao(),
  };

  Widget _tituloAzul(String texto) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
    child: Text(
      texto,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Colors.blue[300],
      ),
    ),
  );

  /// Parte fixa de cada seção (não rola).
  List<Widget> _fixoDaSecao() => switch (_secao) {
    2 => [_tituloAzul('Contagem de Animais Hoje')],
    _ => [
      _tituloAzul('Identificação'),
      // painel cinza com as caixas brancas, como nas outras telas
      _painelCinza(_camposDaSecao()),
      _tituloAzul('Atividades do Dia'),
    ],
  };

  Widget _painelCinza(List<Widget> filhos) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.grey[200],
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: filhos,
    ),
  );

  /// Parte que rola em cada seção (por trás do botão Próximo).
  List<Widget> _rolavelDaSecao() => switch (_secao) {
    1 => _atividadesDoDia(),
    2 => _conferenciaRebanho(),
    _ => const [],
  };

  // ---------------------------------------------------------------------
  // Seção 2 — Conferência de Rebanho
  // ---------------------------------------------------------------------

  Widget _pergunta(String texto) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
    child: Text(
      texto,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Color(0xFF455A64),
      ),
    ),
  );

  /// Opções lado a lado: a escolhida fica azul cheia, as outras com borda.
  Widget _opcoes(
    List<(String, String)> opcoes,
    String? escolhida,
    ValueChanged<String> aoEscolher,
  ) {
    return Row(
      children: [
        for (var i = 0; i < opcoes.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              // mais quadradas, como no modelo
              height: 84,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  backgroundColor: escolhida == opcoes[i].$1
                      ? _azulBotao
                      : Colors.white,
                  foregroundColor: escolhida == opcoes[i].$1
                      ? Colors.white
                      : _azulBotao,
                  side: const BorderSide(color: _azulBotao),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  aoEscolher(opcoes[i].$1);
                },
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    opcoes[i].$2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _conferenciaRebanho() => [
    _pergunta('Conferiu o Gado?'),
    _opcoes(
      const [
        ('todo', 'Gado Todo'),
        ('parte', 'Parte do Gado'),
        ('nao', 'Não Conferi'),
      ],
      _conferiuGado,
      (v) => setState(() => _conferiuGado = v),
    ),
    // os totais só com "Gado Todo" ou "Parte do Gado"
    if (_conferiuGado == 'todo' || _conferiuGado == 'parte') ...[
      const SizedBox(height: 10),
      _painelCinza([
        CampoTextoTopo(
          rotulo: '* Totais de Animais Esperados',
          rotuloNegrito: 'Esperados',
          altura: 80,
          corRotulo: _corRotulo,
          controller: _esperadosController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => _totaisMudaram(),
        ),
        const SizedBox(height: 8),
        CampoTextoTopo(
          rotulo: '* Totais de Animais Encontrados',
          rotuloNegrito: 'Encontrados',
          altura: 80,
          corRotulo: _corRotulo,
          controller: _encontradosController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => _totaisMudaram(),
        ),
        // Totais diferentes: a diferença (só leitura) e os pastos
        if ((_diferenca ?? 0) != 0) ...[
          const SizedBox(height: 8),
          CampoValorTopo(
            rotulo: _diferenca! < 0 ? 'Quantos Faltaram' : 'Quantos Sobraram',
            altura: 80,
            corRotulo: _corRotulo,
            valor: '${_diferenca!.abs()}',
          ),
          const SizedBox(height: 8),
          CampoValorTopo(
            rotulo: '* Em qual(is) pasto(s) está a diferença?',
            corRotulo: _corRotulo,
            valor: _pastosDiferenca.isEmpty
                ? ''
                : '${_pastosDiferenca.length} pasto(s) selecionado(s)',
            icone: Icon(Icons.arrow_drop_down, color: _corRotulo),
            onTap: _escolherPastos,
          ),
          if (_pastosDiferenca.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                _nomesPastosDiferenca,
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: _corRotulo,
                ),
              ),
            ),
        ],
      ]),
    ],
    _pergunta('Conferiu as Vacas Prenhas?'),
    _opcoes(
      const [('sim', 'SIM'), ('nao', 'NÃO'), ('sem', 'Sem Vacas Prenhas')],
      _conferiuPrenhas,
      (v) => setState(() => _conferiuPrenhas = v),
    ),
    const SizedBox(height: 14),
    _painelCinza([
      CampoTextoTopo(
        rotulo: 'Observação Sobre o Rebanho',
        corRotulo: _corRotulo,
        controller: _obsRebanhoController,
        altura: null,
        linhas: 3,
        dica: 'Comentar problemas do rebanho',
        textCapitalization: TextCapitalization.sentences,
      ),
    ]),
  ];

  /// Seção 1 — "Atividades do Dia"  /// Seção 1 — "Atividades do Dia": caixas de marcar, uma por atividade.
  List<Widget> _atividadesDoDia() => [
    for (final a in _atividades) ...[
      _atividade(a.$1, a.$2, a.$3, a.$4),
      const SizedBox(height: 8),
    ],
  ];

  Widget _atividade(
    String chave,
    String texto,
    IconData? icone,
    String? imagem,
  ) {
    const azulIcone = Color(0xFF228cb9);
    final marcada = _atividadesMarcadas.contains(chave);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _marcarAtividade(chave, !marcada),
      child: Container(
        height: 54,
        padding: const EdgeInsets.only(left: 4, right: 12),
        decoration: BoxDecoration(
          color: marcada ? const Color(0xFFE3F2FD) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: marcada ? _azulBotao : const Color(0xFFCFD8DC),
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: marcada,
              activeColor: _azulBotao,
              // quadrado com a borda fina
              side: const BorderSide(width: 1.2, color: Color(0xFF90A4AE)),
              visualDensity: VisualDensity.compact,
              onChanged: (v) => _marcarAtividade(chave, v ?? false),
            ),
            if (imagem != null)
              Image.asset(
                'assets/images/$imagem',
                width: 24,
                height: 24,
                color: azulIcone,
              )
            else
              Icon(icone, size: 24, color: azulIcone),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                texto,
                style: TextStyle(fontSize: 15, color: _corRotulo),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Seção 1 — Identificação.
  List<Widget> _secaoIdentificacao() => [
    CampoValorTopo(
      rotulo: '* Data do Registro',
      corRotulo: _corRotulo,
      valor: _formatar(_data),
      icone: Icon(Icons.calendar_month, color: _corRotulo, size: 20),
      onTap: _escolherData,
    ),
    const SizedBox(height: 10),
    SeletorCampoWidget<String>(
      rotulo: '* Fazenda',
      corRotulo: _corRotulo,
      valor: _fazenda,
      opcoes: _fazendas,
      destaque: true,
      onChanged: (v) => setState(() => _fazenda = v),
    ),
    const SizedBox(height: 10),
    // o usuário logado, sem digitar
    CampoValorTopo(
      rotulo: 'Responsável (quem fez o resumo)',
      corRotulo: _corRotulo,
      valor: _responsavel,
    ),
  ];
}
