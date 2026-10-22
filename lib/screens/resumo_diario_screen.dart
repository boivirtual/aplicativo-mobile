import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// A navegação entre as seções vem nas próximas etapas.
  void _proximo() {}

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
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              children: _camposDaSecao(),
            ),
          ),
          // Próximo fixo embaixo, como no modelo
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
                          style: TextStyle(fontSize: 16, color: Colors.white),
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
    1 => 'Identificação',
    _ => '',
  };

  List<Widget> _camposDaSecao() => switch (_secao) {
    _ => _secaoIdentificacao(),
  };

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
