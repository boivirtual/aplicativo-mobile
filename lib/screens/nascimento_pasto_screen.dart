import 'package:flutter/material.dart';

import '../widgets/indicador_conectividade_widget.dart';

/// Tela "Mapa de Gado - Nascimento" (modal #modal_nascimento do web, em
/// form_mapa_gados_movimentacao.php). No aplicativo é uma tela própria,
/// porque o formulário é extenso demais para um modal.
///
/// Só abre com o aplicativo online (ver _abrirNascimento em
/// PastoMovimentacaoWidget).
///
/// Por enquanto tem só o começo: tarja com a fazenda e o pasto e as
/// opções (Nascimento, Aborto, Absorção e Natimorto). Os
/// campos de cada opção são a próxima etapa.
class NascimentoPastoScreen extends StatefulWidget {
  final String bd;
  final int fazendaId;
  final String fazendaCodigo;
  final String nomeFazenda;
  final int pastoId;
  final String nomePasto;
  final String? usuario;

  const NascimentoPastoScreen({
    super.key,
    required this.bd,
    required this.fazendaId,
    required this.fazendaCodigo,
    required this.nomeFazenda,
    required this.pastoId,
    required this.nomePasto,
    required this.usuario,
  });

  @override
  State<NascimentoPastoScreen> createState() => _NascimentoPastoScreenState();
}

class _NascimentoPastoScreenState extends State<NascimentoPastoScreen> {
  static const _azul = Color(0xFF18385F);
  static final _corRotulo = Colors.blueGrey[800]!;

  /// Mesmos valores do web (radio opcao_nascimento): N = Nascimento,
  /// A = Aborto, B = Absorção, M = Natimorto.
  static const _opcoes = [
    MapEntry('N', 'Nascimento'),
    MapEntry('A', 'Aborto'),
    MapEntry('B', 'Absorção'),
    MapEntry('M', 'Natimorto'),
  ];

  String? _opcao;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Mapa de Gado - Nascimento',
          style: TextStyle(fontSize: 18, color: Colors.white),
        ),
        backgroundColor: _azul,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: const [IndicadorConectividadeWidget(), SizedBox(width: 8)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 16),
        children: [
          _cabecalho(),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 14, color: _corRotulo),
                children: const [
                  TextSpan(
                    text: '* ',
                    style: TextStyle(color: Colors.red),
                  ),
                  TextSpan(text: 'Selecione uma opção'),
                ],
              ),
            ),
          ),
          Row(
            children: [
              for (final o in _opcoes)
                Expanded(
                  // mais espaço para o texto mais comprido
                  flex: o.value.length + 4,
                  child: _opcaoWidget(o.key, o.value),
                ),
            ],
          ),
          Divider(color: Colors.grey[200], height: 16),
        ],
      ),
    );
  }

  /// Tarja azul no mesmo padrão da tela do pasto, com a fazenda e o pasto
  /// na mesma linha (a fonte encolhe um pouco se o nome for comprido).
  Widget _cabecalho() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '${widget.nomeFazenda}  -  Pasto: ${widget.nomePasto}',
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.blue,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _opcaoWidget(String valor, String texto) {
    final marcado = _opcao == valor;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _opcao = valor),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        // Sempre em uma linha: a fonte encolhe um pouco se não couber.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                marcado ? Icons.radio_button_checked : Icons.radio_button_off,
                color: marcado ? _azul : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(texto, style: TextStyle(fontSize: 14, color: _corRotulo)),
            ],
          ),
        ),
      ),
    );
  }
}
