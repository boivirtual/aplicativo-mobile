import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/daos/mapa_gado_dao.dart';
import '../services/mapa_gado_sync_service.dart';
import '../utils/app_alert.dart';
import '../widgets/seletor_campo_widget.dart';
import 'composicao_descricao_lote_screen.dart' show perguntarSimNao;

/// "Mapa de Gado - Nutrição" — botão Nutrição da tela do pasto, igual ao
/// modal do web (form_mapa_gados_movimentacao.php): Situação do Cocho,
/// Data, Produto, Quantidade, Und, "Confirmar Inclusão" e a tabela das
/// nutrições do pasto na data, com a lixeira.
///
/// Funciona offline: as listas e as nutrições recentes vêm do cache local;
/// incluir/excluir aparecem na tabela na hora e entram na fila do mapa
/// (mesma regra de gravar_nutricao.php, repetida no servidor quando a fila
/// é enviada). Com internet, ao trocar a data a tabela é buscada no
/// servidor.
class NutricaoPastoModal extends StatefulWidget {
  final String bd;
  final int fazendaId;
  final String nomeFazenda;
  final int pastoId;
  final String nomePasto;

  /// Animais ativos no pasto (vai para "Qtd Animais" da nutrição).
  final int totalAnimais;
  final String? usuario;

  const NutricaoPastoModal({
    super.key,
    required this.bd,
    required this.fazendaId,
    required this.nomeFazenda,
    required this.pastoId,
    required this.nomePasto,
    required this.totalAnimais,
    required this.usuario,
  });

  @override
  State<NutricaoPastoModal> createState() => _NutricaoPastoModalState();
}

class _NutricaoPastoModalState extends State<NutricaoPastoModal> {
  static const _azulTitulo = Color(0xFF18385F);
  static const _verde = Color(0xFF4CAF50);
  static const _azulVoltar = Color(0xFF4BBAEB);
  static final Color _corRotulo = Colors.blueGrey.shade800;

  final _qtdController = TextEditingController();

  List<MapEntry<int, String>> _cochos = [];
  List<Map<String, dynamic>> _produtos = [];
  List<Map<String, Object?>> _itens = [];

  int? _cocho;
  int? _produto;
  DateTime _data = _hoje();
  bool _gravando = false;

  static DateTime _hoje() {
    final a = DateTime.now();
    return DateTime(a.year, a.month, a.day);
  }

  static String _br(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 1234.5 -> "1.234,50" (number_format(x, 2, ",", ".") do web).
  static String _decimal(num valor) {
    final fixo = valor.abs().toStringAsFixed(2).split('.');
    final inteiro = fixo[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return '${valor < 0 ? '-' : ''}$inteiro,${fixo[1]}';
  }

  String get _unidade {
    final p = _produtos.where((p) => p['id'] == _produto).firstOrNull;
    return (p?['unidade'] ?? '').toString();
  }

  @override
  void initState() {
    super.initState();
    // A fila enviou algo (ex: a inclusão ganhou o id do servidor): relê.
    MapaGadoSyncService.instance.versaoFila.addListener(_lerItens);
    _carregar();
  }

  @override
  void dispose() {
    MapaGadoSyncService.instance.versaoFila.removeListener(_lerItens);
    _qtdController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final dao = MapaGadoDao.instance;
    final cochos = await dao.scoresCocho(widget.bd);
    final produtos = await dao.produtosNutricao(widget.bd);
    if (!mounted) return;
    setState(() {
      _cochos = cochos;
      _produtos = produtos;
    });
    await _lerNutricao();
  }

  Future<void> _lerItens() async {
    final itens = await MapaGadoDao.instance.nutricoesDoPasto(
      widget.bd,
      widget.pastoId,
      _iso(_data),
    );
    if (mounted) setState(() => _itens = itens);
  }

  /// lerNutricao() do web: a tabela da data escolhida. Mostra o que está
  /// no aparelho e, com internet, confere no servidor.
  Future<void> _lerNutricao() async {
    await _lerItens();
    final data = _data;
    final ok = await MapaGadoSyncService.instance.buscarNutricoesDoDia(
      bd: widget.bd,
      fazenda: widget.fazendaId,
      pasto: widget.pastoId,
      data: _iso(data),
    );
    if (ok && mounted && data == _data) await _lerItens();
  }

  Future<void> _escolherData() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: _hoje(), // a data não pode ser maior que a data atual
      helpText: 'Data',
    );
    if (d == null || !mounted) return;
    setState(() => _data = d);
    await _lerNutricao();
  }

  Future<void> _confirmarInclusao() async {
    if (_gravando) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final quantidade = double.tryParse(
      _qtdController.text.trim().replaceAll(',', '.'),
    );
    final cocho = _cocho;
    final produto = _produtos.where((p) => p['id'] == _produto).firstOrNull;
    if (cocho == null ||
        produto == null ||
        quantidade == null ||
        _unidade.isEmpty) {
      await AppAlert.erro(context, 'Preencha todos os campos da nutrição!');
      return;
    }
    if (_data.isAfter(_hoje())) {
      await AppAlert.erro(context, 'A Data não pode ser maior que a data atual!');
      return;
    }

    setState(() => _gravando = true);
    try {
      await MapaGadoSyncService.instance.incluirNutricao(
        bd: widget.bd,
        fazenda: widget.fazendaId,
        pasto: widget.pastoId,
        data: _iso(_data),
        produto: produto['id'] as int,
        produtoDescricao: (produto['descricao'] ?? '').toString(),
        unidade: _unidade,
        quantidade: quantidade,
        qtdAnimais: widget.totalAnimais,
        cocho: cocho,
        usuario: widget.usuario,
      );
      if (!mounted) return;
      await AppAlert.sucesso(context, 'Registro gravado com sucesso.');
      if (!mounted) return;
      // fecharNutricao() do web: limpa os campos (a data fica).
      setState(() {
        _cocho = null;
        _produto = null;
        _qtdController.clear();
      });
      await _lerItens();
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  Future<void> _excluir(Map<String, Object?> item) async {
    final ok = await perguntarSimNao(
      context,
      titulo: 'Mapa de Gado - Nutrição',
      mensagem: 'Tem certeza que deseja enviar o registro para a lixeira?',
    );
    if (!ok || !mounted) return;
    await MapaGadoSyncService.instance.excluirNutricao(
      bd: widget.bd,
      chave: (item['chave'] ?? '').toString(),
      id: (item['id'] as int?) ?? 0,
      usuario: widget.usuario,
    );
    if (!mounted) return;
    await _lerItens();
    if (!mounted) return;
    await AppAlert.sucesso(context, 'Registro excluido com sucesso.');
  }

  // ---------------------------------------------------------------------
  // Layout — padrão dos modais do aplicativo (Morte, Composição do Lote)
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Mapa de Gado - Nutrição',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: _azulTitulo),
              ),
              const SizedBox(height: 10),
              _tarja(),
              const SizedBox(height: 10),
              SeletorCampoWidget<int>(
                rotulo: '* Situação do Cocho',
                corRotulo: _corRotulo,
                valor: _cocho,
                opcoes: _cochos,
                onChanged: (v) => setState(() => _cocho = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: SeletorCampoWidget<int>(
                      rotulo: '* Produto',
                      corRotulo: _corRotulo,
                      valor: _produto,
                      opcoes: [
                        for (final p in _produtos)
                          MapEntry(p['id'] as int, p['descricao'].toString()),
                      ],
                      onChanged: (v) => setState(() => _produto = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(flex: 3, child: _campoData()),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: _caixa(
                      child: TextField(
                        controller: _qtdController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        style: const TextStyle(fontSize: 15),
                        decoration: _decoracao('* Quantidade'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(flex: 3, child: _campoFixo('Und', _unidade)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: _botao(
                      'Confirmar Inclusão',
                      _verde,
                      _confirmarInclusao,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: _botao(
                      'Voltar',
                      _azulVoltar,
                      () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
              if (_itens.isNotEmpty) ...[
                const SizedBox(height: 12),
                _tabela(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarja() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.blue.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      children: [
        Text(
          widget.nomeFazenda,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Colors.blue),
        ),
        Text(
          'Pasto: ${widget.nomePasto}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.blue,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

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

  /// Rótulo pequeno em cima e o valor embaixo (mesmo desenho do select).
  Widget _rotuloValor(String rotulo, String valor, {Widget? icone}) => Padding(
    padding: const EdgeInsets.only(left: 12, right: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo, style: TextStyle(fontSize: 11, color: _corRotulo)),
              const SizedBox(height: 2),
              Text(
                valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
            ],
          ),
        ),
        if (icone != null) icone,
      ],
    ),
  );

  Widget _campoData() => GestureDetector(
    onTap: _escolherData,
    child: _caixa(
      child: _rotuloValor(
        '* Data',
        _br(_data),
        icone: Icon(Icons.calendar_month, color: _corRotulo, size: 18),
      ),
    ),
  );

  /// Campo só de leitura (Und vem do produto, como no web).
  Widget _campoFixo(String rotulo, String valor) =>
      _caixa(child: _rotuloValor(rotulo, valor));

  Widget _botao(String texto, Color cor, VoidCallback aoTocar) => SizedBox(
    height: 45,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: cor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: aoTocar,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          texto,
          style: const TextStyle(fontSize: 15, color: Colors.white),
        ),
      ),
    ),
  );

  // Tabela: Data | Produto | Quantidade | Und | Qtd Animais | Média/Cabeças
  static const _larguras = <int, TableColumnWidth>{
    0: FixedColumnWidth(58),
    1: FlexColumnWidth(),
    2: FixedColumnWidth(50),
    3: FixedColumnWidth(26),
    4: FixedColumnWidth(44),
    5: FixedColumnWidth(48),
    6: FixedColumnWidth(30),
  };

  Widget _tabela() {
    Widget cab(String t, {TextAlign alinhamento = TextAlign.left}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: Text(
        t,
        textAlign: alinhamento,
        style: const TextStyle(
          fontSize: 10,
          color: Color(0xFF5B8A72),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    Widget cel(String t, {TextAlign alinhamento = TextAlign.left}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      child: Text(
        t,
        textAlign: alinhamento,
        style: const TextStyle(fontSize: 11, color: Color(0xFF444444)),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Table(
        columnWidths: _larguras,
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFDDDDDD))),
            ),
            children: [
              cab('Data'),
              cab('Produto'),
              cab('Quant.', alinhamento: TextAlign.right),
              cab('Und', alinhamento: TextAlign.center),
              cab('Qtd Animais', alinhamento: TextAlign.center),
              cab('Média/ Cabeças', alinhamento: TextAlign.right),
              const SizedBox.shrink(),
            ],
          ),
          for (final item in _itens)
            TableRow(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
              ),
              children: [
                cel(_br(DateTime.tryParse('${item['data']}') ?? _data)),
                cel('${item['produto'] ?? ''}'),
                cel(
                  _decimal((item['quantidade'] as num?) ?? 0),
                  alinhamento: TextAlign.right,
                ),
                cel('${item['unidade'] ?? ''}', alinhamento: TextAlign.center),
                cel(
                  '${item['qtd_animais'] ?? 0}'.padLeft(4, '0'),
                  alinhamento: TextAlign.center,
                ),
                cel(
                  _decimal((item['media_cabeca'] as num?) ?? 0),
                  alinhamento: TextAlign.right,
                ),
                InkWell(
                  onTap: () => _excluir(item),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Color(0xFF128CB8),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
