import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // muda quando o Próximo passar a avançar entre as seções
  // ignore: prefer_final_fields
  int _secao = 1;

  DateTime _data = _hoje();
  List<MapEntry<String, String>> _fazendas = [];
  String? _fazenda;
  String _responsavel = '';

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

  /// Só avança com a seção atual preenchida. A ida para a Seção 2 vem nas
  /// próximas etapas.
  Future<void> _proximo() async {
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
    }
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
                    96 + MediaQuery.of(context).padding.bottom,
                  ),
                  children: _rolavelDaSecao(),
                ),
                // Próximo sempre visível; a tela rola por trás dele
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
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: 170,
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
  List<Widget> _fixoDaSecao() => [
    if (_secao == 1) _tituloAzul('Identificação'),
    // painel cinza com as caixas brancas, como nas outras telas
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _camposDaSecao(),
      ),
    ),
    if (_secao == 1) _tituloAzul('Atividades do Dia'),
  ];

  /// Parte que rola em cada seção (por trás do botão Próximo).
  List<Widget> _rolavelDaSecao() => switch (_secao) {
    1 => _atividadesDoDia(),
    _ => const [],
  };

  /// Seção 1 — "Atividades do Dia": caixas de marcar, uma por atividade.
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
