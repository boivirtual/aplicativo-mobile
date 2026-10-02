import 'package:flutter/material.dart';
import '../utils/app_alert.dart';
import '../utils/descricao_lote_composicao.dart';
import '../widgets/seletor_campo_widget.dart';

/// Resultado de "Criar nova Descrição do Lote".
class NovaDescricaoLote {
  final String descricao;
  final List<String> lotes;
  const NovaDescricaoLote(this.descricao, this.lotes);
}

/// Pergunta Sim/Não no padrão das mensagens do mapa no web
/// ("Mapa de Gado - Mensagem").
Future<bool> perguntarSimNao(
  BuildContext context, {
  required String titulo,
  required String mensagem,
}) async {
  // Sem isso, ao fechar a pergunta o Flutter devolve o foco ao último
  // campo de texto da tela (a busca do mapa) e abre o teclado sozinho.
  FocusManager.instance.primaryFocus?.unfocus();
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    requestFocus: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      content: Text(mensagem),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Não'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(
            'Sim',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
          ),
        ),
      ],
    ),
  );
  FocusManager.instance.primaryFocus?.unfocus();
  return r == true;
}

/// "Composição da Descrição do Lote" — aberta depois de mover todos os
/// animais para um pasto que JÁ tinha descrição do lote (igual ao
/// tabuleiro do web). O usuário escolhe:
///   - Manter a Descrição do Lote  -> devolve null;
///   - Criar nova Descrição do Lote -> monta até 6 lotes e devolve
///     [NovaDescricaoLote].
/// Não fecha sem uma escolha (no web o modal também é estático).
class ComposicaoDescricaoLoteScreen extends StatefulWidget {
  final String nomePasto;
  final String descricaoAtual;
  final List<MapEntry<int, String>> descricoes;

  const ComposicaoDescricaoLoteScreen({
    super.key,
    required this.nomePasto,
    required this.descricaoAtual,
    required this.descricoes,
  });

  @override
  State<ComposicaoDescricaoLoteScreen> createState() =>
      _ComposicaoDescricaoLoteScreenState();
}

class _ComposicaoDescricaoLoteScreenState
    extends State<ComposicaoDescricaoLoteScreen> {


  /// 'M' manter, 'N' nova (mesmos valores do web).
  String? _opcao;

  // Lotes já incluídos.
  final List<String> _linhas = [];

  // Lote em edição.
  int? _descricaoId;
  int? _parametro2;
  bool _comData = false;
  final List<DateTime> _datas = [];

  String get _descricaoTexto => widget.descricoes
      .firstWhere(
        (d) => d.key == _descricaoId,
        orElse: () => const MapEntry(0, ''),
      )
      .value;

  String? get _parametro2Texto {
    if (_descricaoId == null || _parametro2 == null) return null;
    return DescricaoLoteComposicao.opcoesParametro2(_descricaoId!)
        .firstWhere((o) => o.key == _parametro2, orElse: () => const MapEntry(0, ''))
        .value;
  }

  String get _linhaAtual => _descricaoId == null
      ? ''
      : DescricaoLoteComposicao.montarLinha(
          descricao: _descricaoTexto,
          parametro2: _parametro2Texto,
          datas: _comData ? _datas : const [],
        );

  void _limparEditor() {
    _descricaoId = null;
    _parametro2 = null;
    _comData = false;
    _datas.clear();
  }

  Future<void> _escolherManter() async {
    setState(() => _opcao = 'M');
    final ok = await perguntarSimNao(
      context,
      titulo: 'Composição da Descrição do Lote',
      mensagem: 'Confirma Manter a Descrição do Lote do Pasto ${widget.nomePasto}',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _opcao = null);
    }
  }

  Future<void> _incluirMaisLote() async {
    final erro = DescricaoLoteComposicao.validarLinha(_descricaoId, _parametro2);
    if (erro != null) {
      await AppAlert.erro(context, erro);
      return;
    }
    if (_linhas.length >= DescricaoLoteComposicao.maxLotes) {
      await AppAlert.erro(context, 'Só é possível incluir seis lotes de animais.');
      return;
    }
    setState(() {
      _linhas.add(_linhaAtual);
      _limparEditor();
    });
  }

  Future<void> _confirmar() async {
    final linhas = [..._linhas];
    if (_descricaoId != null || linhas.isEmpty) {
      final erro = DescricaoLoteComposicao.validarLinha(_descricaoId, _parametro2);
      if (erro != null) {
        await AppAlert.erro(context, erro);
        return;
      }
      if (linhas.length >= DescricaoLoteComposicao.maxLotes) {
        await AppAlert.erro(context, 'Só é possível incluir seis lotes de animais.');
        return;
      }
      linhas.add(_linhaAtual);
    }
    final descricao = DescricaoLoteComposicao.montarDescricao(linhas);
    if (descricao.isEmpty) {
      if (!mounted) return;
      await AppAlert.erro(context, 'A Descrição do Lote não pode ser vazia.');
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, NovaDescricaoLote(descricao, linhas));
  }

  Future<void> _adicionarData() async {
    final d = await _escolherMesAno(context);
    if (d != null) setState(() => _datas.add(d));
  }

  // ---------------------------------------------------------------------
  // Layout no padrão do modal "Editar Pesagem" (pesagem_edicao_modal.dart):
  // caixa cinza claro com cantos 12, título azul em negrito, campos brancos
  // sem borda (cantos 8, rótulo azul acinzentado) e botão com cantos 8.
  // ---------------------------------------------------------------------

  static const _azulTitulo = Color(0xFF18385F);
  static const _verde = Color(0xFF4CAF50);
  static final Color _corRotulo = Colors.blueGrey.shade800;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                  'Composição da Descrição do Lote',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _azulTitulo,
                  ),
                ),
                const SizedBox(height: 10),
                _caixaPasto(),
                const SizedBox(height: 10),
                _opcaoLote('M', 'Manter a Descrição do Lote'),
                const SizedBox(height: 8),
                _opcaoLote('N', 'Criar nova Descrição do Lote'),
                if (_opcao == 'N') ...[
                  const SizedBox(height: 14),
                  ..._buildLinhasIncluidas(),
                  _buildEditor(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _incluirMaisLote,
                      icon: const Icon(Icons.add, size: 18, color: _azulTitulo),
                      label: const Text(
                        'Incluir mais lote',
                        style: TextStyle(color: _azulTitulo),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 45,
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
                        'Confirmar',
                        style: TextStyle(fontSize: 15, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Pasto e a descrição atual — tarja azul no padrão da Pesagem.
  Widget _caixaPasto() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            widget.nomePasto,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.blue,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (widget.descricaoAtual.isNotEmpty)
            Text(
              widget.descricaoAtual,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _opcaoLote(String valor, String texto) {
    final marcado = _opcao == valor;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (valor == 'M') {
            _escolherManter();
          } else if (_opcao != 'N') {
            setState(() {
              _opcao = 'N';
              _linhas.clear();
              _limparEditor();
            });
          }
        },
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(
                marcado ? Icons.radio_button_checked : Icons.radio_button_off,
                color: marcado ? _azulTitulo : Colors.grey,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  texto,
                  style: TextStyle(fontSize: 14, color: _corRotulo),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLinhasIncluidas() {
    return [
      for (var i = 0; i < _linhas.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(_linhas[i], style: const TextStyle(fontSize: 14)),
              ),
              IconButton(
                tooltip: 'Excluir esse lote',
                icon: const Icon(Icons.delete_outline, color: Color(0xFF128CB8)),
                onPressed: () => setState(() => _linhas.removeAt(i)),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _buildEditor() {
    final opcoes2 = _descricaoId == null
        ? const <MapEntry<int, String>>[]
        : DescricaoLoteComposicao.opcoesParametro2(_descricaoId!);
    final mostraPergunta =
        _descricaoId != null &&
        DescricaoLoteComposicao.perguntaData(_descricaoId!, _parametro2);
    final rotuloData = _descricaoId == null
        ? 'Parição'
        : DescricaoLoteComposicao.rotuloData(_descricaoId!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SeletorCampoWidget<int>(
          rotulo: '* Descrição do Lote',
          corRotulo: _corRotulo,
          valor: _descricaoId,
          opcoes: widget.descricoes,
          onChanged: (v) => setState(() {
            _descricaoId = v;
            _parametro2 = null;
            _comData = false;
            _datas.clear();
          }),
        ),
        if (opcoes2.isNotEmpty) ...[
          const SizedBox(height: 8),
          SeletorCampoWidget<int>(
            rotulo: '* ${DescricaoLoteComposicao.rotuloParametro2(_descricaoId!)}',
            corRotulo: _corRotulo,
            valor: _parametro2,
            opcoes: opcoes2,
            onChanged: (v) => setState(() {
              _parametro2 = v;
              _comData = false;
              _datas.clear();
            }),
          ),
        ],
        if (mostraPergunta) ...[
          const SizedBox(height: 8),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: CheckboxListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              activeColor: _azulTitulo,
              value: _comData,
              title: Text(
                'Informar Data da $rotuloData?',
                style: TextStyle(fontSize: 14, color: _corRotulo),
              ),
              onChanged: (v) => setState(() {
                _comData = v ?? false;
                if (!_comData) _datas.clear();
              }),
            ),
          ),
        ],
        if (mostraPergunta && _comData) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < _datas.length; i++)
                InputChip(
                  backgroundColor: Colors.white,
                  label: Text(
                    DescricaoLoteComposicao.formatarMesAno(_datas[i]),
                  ),
                  onDeleted: () => setState(() => _datas.removeAt(i)),
                ),
              TextButton.icon(
                onPressed: _adicionarData,
                icon: const Icon(
                  Icons.calendar_month,
                  size: 18,
                  color: _azulTitulo,
                ),
                label: Text(
                  _datas.isEmpty
                      ? 'Mês/Ano da $rotuloData'
                      : 'Incluir mais Data',
                  style: const TextStyle(color: _azulTitulo),
                ),
              ),
            ],
          ),
        ],
        if (_linhaAtual.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _linhaAtual,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.blue,
            ),
          ),
        ],
      ],
    );
  }
}

/// Seletor simples de mês/ano (equivalente ao <input type="month"> do web).
Future<DateTime?> _escolherMesAno(BuildContext context) {
  const meses = [
    'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
    'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
  ];
  var ano = DateTime.now().year;
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setStateDialog) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setStateDialog(() => ano--),
            ),
            Text('$ano'),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setStateDialog(() => ano++),
            ),
          ],
        ),
        content: SizedBox(
          width: 280,
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4,
            childAspectRatio: 1.6,
            children: [
              for (var m = 1; m <= 12; m++)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, DateTime(ano, m)),
                  child: Text(meses[m - 1]),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    ),
  );
}
