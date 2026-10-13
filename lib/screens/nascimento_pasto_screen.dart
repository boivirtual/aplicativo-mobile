import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/indicador_conectividade_widget.dart';
import '../widgets/seletor_campo_widget.dart';

/// Tela "Mapa de Gado - Nascimento" (modal #modal_nascimento do web, em
/// form_mapa_gados_movimentacao.php). No aplicativo é uma tela própria,
/// porque o formulário é extenso demais para um modal.
///
/// Só abre com o aplicativo online (ver _abrirNascimento em
/// PastoMovimentacaoWidget).
///
/// Por enquanto são só as telas (controle de estoque por animal), com os
/// mesmos campos que o web mostra em cada opção:
///   - Nascimento: Data Nascimento, Nº Mãe, Pai Nº, Nº Animal, Monta,
///     Sexo, Raça, Pelagem e Peso;
///   - Aborto, Absorção e Natimorto: Data Ocorrência, Nº Fêmea e Sexo.
/// As listas (Pai, Raça e Pelagem), as validações e a gravação são a
/// próxima etapa.
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
  static const _verde = Color(0xFF4CAF50);
  static final _corRotulo = Colors.blueGrey[800]!;

  /// Mesmos valores do web (radio opcao_nascimento): N = Nascimento,
  /// A = Aborto, B = Absorção, M = Natimorto.
  static const _opcoes = [
    MapEntry('N', 'Nascimento'),
    MapEntry('A', 'Aborto'),
    MapEntry('B', 'Absorção'),
    MapEntry('M', 'Natimorto'),
  ];

  final _maeController = TextEditingController();
  final _animalController = TextEditingController();
  final _pesoController = TextEditingController();

  String? _opcao;
  DateTime _data = _hoje();
  String? _sexo; // 'M' ou 'F'
  String? _pai;
  String? _raca;
  String? _pelagem;

  // Listas dos selects: vêm do servidor na próxima etapa.
  final List<MapEntry<String, String>> _pais = const [];
  final List<MapEntry<String, String>> _racas = const [];
  final List<MapEntry<String, String>> _pelagens = const [];

  static DateTime _hoje() {
    final a = DateTime.now();
    return DateTime(a.year, a.month, a.day);
  }

  static String _formatar(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  void dispose() {
    _maeController.dispose();
    _animalController.dispose();
    _pesoController.dispose();
    super.dispose();
  }

  /// Como no web: trocar de opção limpa os campos.
  void _escolherOpcao(String valor) {
    if (_opcao == valor) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _opcao = valor;
      _data = _hoje();
      _sexo = null;
      _pai = null;
      _raca = null;
      _pelagem = null;
      _maeController.clear();
      _animalController.clear();
      _pesoController.clear();
    });
  }

  Future<void> _escolherData() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: _hoje(),
      helpText: _opcao == 'N' ? 'Data do nascimento' : 'Data da ocorrência',
    );
    if (d != null) setState(() => _data = d);
  }

  /// A gravação é a próxima etapa.
  void _confirmar() => FocusManager.instance.primaryFocus?.unfocus();

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
            child: _rotuloObrigatorio('Selecione uma opção', 14),
          ),
          Row(
            children: [
              for (final o in _opcoes)
                Expanded(
                  // mais espaço para o texto mais comprido
                  flex: o.value.length + 4,
                  child: _radio(
                    o.value,
                    marcado: _opcao == o.key,
                    aoTocar: () => _escolherOpcao(o.key),
                  ),
                ),
            ],
          ),
          if (_opcao != null) ...[
            const SizedBox(height: 6),
            // Painel cinza com as caixas brancas: mesmo padrão dos modais
            // de Morte e Nutrição.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_opcao == 'N')
                    ..._camposNascimento()
                  else
                    ..._camposOcorrencia(),
                  const SizedBox(height: 10),
                  _botao('Confirmar', _verde, _confirmar),
                ],
              ),
            ),
          ] else
            Divider(color: Colors.grey[200], height: 16),
        ],
      ),
    );
  }

  /// Opção Nascimento.
  List<Widget> _camposNascimento() => [
    Row(
      children: [
        Expanded(child: _campoData('* Data Nascimento')),
        const SizedBox(width: 8),
        Expanded(child: _campoTexto('* Nº Mãe', _maeController)),
      ],
    ),
    const SizedBox(height: 8),
    _seletor('Pai Nº', _pai, _pais, (v) => setState(() => _pai = v)),
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(
          child: _campoTexto('Nº Animal', _animalController, numerico: true),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'Monta:',
              style: TextStyle(fontSize: 14, color: _corRotulo),
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 8),
    _campoSexo(),
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(
          child: _seletor(
            '* Raça',
            _raca,
            _racas,
            (v) => setState(() => _raca = v),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _seletor(
            'Pelagem',
            _pelagem,
            _pelagens,
            (v) => setState(() => _pelagem = v),
          ),
        ),
      ],
    ),
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(
          child: _campoTexto('* Peso', _pesoController, numerico: true),
        ),
        const SizedBox(width: 8),
        const Expanded(child: SizedBox()),
      ],
    ),
  ];

  /// Opções Aborto, Absorção e Natimorto (iguais no web).
  List<Widget> _camposOcorrencia() => [
    Row(
      children: [
        Expanded(child: _campoData('* Data Ocorrência')),
        const SizedBox(width: 8),
        Expanded(child: _campoTexto('* Nº Fêmea', _maeController)),
      ],
    ),
    const SizedBox(height: 8),
    _campoSexo(),
  ];

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

  Widget _rotuloObrigatorio(String texto, double fonte) => Text.rich(
    TextSpan(
      style: TextStyle(fontSize: fonte, color: _corRotulo),
      children: [
        const TextSpan(text: '* ', style: TextStyle(color: Colors.red)),
        TextSpan(text: texto),
      ],
    ),
  );

  Widget _radio(
    String texto, {
    required bool marcado,
    required VoidCallback aoTocar,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: aoTocar,
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

  // -----------------------------------------------------------------------
  // Campos — mesmo padrão dos modais de Morte e Nutrição
  // -----------------------------------------------------------------------

  InputDecoration _decoracao(String rotulo) => InputDecoration(
    labelText: rotulo,
    labelStyle: TextStyle(fontSize: 14, color: _corRotulo),
    border: InputBorder.none,
    isDense: true,
    contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
  );

  Widget _caixa({required Widget child}) => Container(
    height: 56,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );

  Widget _campoTexto(
    String rotulo,
    TextEditingController controller, {
    bool numerico = false,
  }) => _caixa(
    child: TextField(
      controller: controller,
      keyboardType: numerico ? TextInputType.number : TextInputType.text,
      inputFormatters: numerico
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      textCapitalization: TextCapitalization.characters,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontSize: 15),
      decoration: _decoracao(rotulo),
    ),
  );

  Widget _campoData(String rotulo) => GestureDetector(
    onTap: _escolherData,
    child: _caixa(
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rotulo,
                    style: TextStyle(fontSize: 11, color: _corRotulo),
                  ),
                  const SizedBox(height: 2),
                  Text(_formatar(_data), style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
            Icon(Icons.calendar_month, color: _corRotulo, size: 20),
          ],
        ),
      ),
    ),
  );

  /// "* Sexo" com Macho e Fêmea, dentro de uma caixa como os outros campos.
  Widget _campoSexo() => _caixa(
    child: Padding(
      padding: const EdgeInsets.only(left: 12, right: 6),
      child: Row(
        children: [
          Text('* Sexo', style: TextStyle(fontSize: 14, color: _corRotulo)),
          const SizedBox(width: 14),
          Expanded(
            child: _radio(
              'Macho',
              marcado: _sexo == 'M',
              aoTocar: () => setState(() => _sexo = 'M'),
            ),
          ),
          Expanded(
            child: _radio(
              'Fêmea',
              marcado: _sexo == 'F',
              aoTocar: () => setState(() => _sexo = 'F'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _seletor(
    String rotulo,
    String? valor,
    List<MapEntry<String, String>> opcoes,
    ValueChanged<String> aoMudar,
  ) => IgnorePointer(
    // sem opções (as listas chegam na próxima etapa) o toque não abre nada
    ignoring: opcoes.isEmpty,
    child: SeletorCampoWidget<String>(
      rotulo: rotulo,
      corRotulo: _corRotulo,
      valor: valor,
      opcoes: opcoes,
      onChanged: aoMudar,
    ),
  );

  Widget _botao(String texto, Color cor, VoidCallback aoTocar) => SizedBox(
    height: 45,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: cor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: aoTocar,
      child: Text(
        texto,
        style: const TextStyle(fontSize: 15, color: Colors.white),
      ),
    ),
  );
}
