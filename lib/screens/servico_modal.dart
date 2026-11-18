import 'package:flutter/material.dart';

import '../data/daos/mapa_gado_dao.dart';
import '../utils/app_alert.dart';
import '../utils/rolar_ate_foco.dart';
import '../widgets/campo_topo_widget.dart';

/// Modal "Serviço(s)" do Resumo Diário (Seção 6 — Serviços, card "Adicionar
/// Serviço"). Mesmo visual e funcionamento do modal "Mistura(s)" da Seção 5:
/// fundo cinza, (x) no canto, conteúdo com rolagem, botão verde que guarda o
/// serviço na lista de baixo (editar e excluir, o último no topo).
///
/// Campos: Tipo (um só, obrigatório) — no Pasto e no Bebedouro também o que
/// precisa ser feito, e no Pasto, Bebedouro e Cocho os pastos da fazenda —, "Descreva o que precisa ser feito
/// e a urgência" e o andamento (Feito / Em andamento / Será feito, um
/// obrigatório). Devolve { servicos } ao fechar pelo (x).
class ServicoModal extends StatefulWidget {
  /// Serviços já incluídos (editar); null = nenhum.
  final List<Map<String, dynamic>>? servicos;

  /// Empresa (CNPJ) e fazenda do resumo: os pastos do Tipo "Pasto" vêm do
  /// Mapa de Gado guardado no aparelho.
  final String bd;
  final String fazenda;

  const ServicoModal({
    super.key,
    this.servicos,
    required this.bd,
    required this.fazenda,
  });

  @override
  State<ServicoModal> createState() => _ServicoModalState();
}

class _ServicoModalState extends State<ServicoModal> {
  static const _azulTitulo = Color(0xFF18385F);
  static const _azulBotao = Color(0xFF007AFF);
  static const _verde = Color(0xFF4CAF50);
  static final _corRotulo = Colors.blueGrey[800]!;

  static const _tipos = [
    'Pasto',
    'Bebedouro',
    'Cocho',
    'Cerca',
    'Curral',
    'Estrada / Acesso',
    'Máquina (manutenção)',
    'Outro',
  ];

  static const _andamentos = <(String, IconData)>[
    ('Feito', Icons.check_circle_outline),
    ('Em andamento', Icons.timelapse),
    ('Será feito', Icons.schedule),
  ];

  String? _tipo;
  final _descricaoController = TextEditingController();
  final _descricaoFoco = FocusNode();
  String? _andamento;

  /// Lista do Tipo aberta embaixo do campo.
  bool _tipoAberto = false;

  /// Serviços já confirmados, na ordem em que foram incluídos.
  final List<Map<String, dynamic>> _servicos = [];

  /// O que precisa ser feito (um ou mais, obrigatório) em cada tipo que tem:
  /// Pasto (Limpeza / Plantio), Bebedouro (Limpeza / Manutenção) e Cerca
  /// (Elétrica / Liso / Farpado).
  static const _acoesPorTipo = <String, List<(String, IconData)>>{
    'Pasto': [
      ('Limpeza', Icons.cleaning_services_outlined),
      ('Plantio', Icons.grass),
    ],
    'Bebedouro': [
      ('Limpeza', Icons.cleaning_services_outlined),
      ('Manutenção', Icons.build_outlined),
    ],
    'Cerca': [
      ('Elétrica', Icons.bolt),
      ('Liso', Icons.horizontal_rule),
      ('Farpado', Icons.fence),
    ],
  };

  /// Tipos que pedem os pastos (vários, obrigatório) da fazenda do resumo.
  static const _tiposComPasto = {
    'Pasto',
    'Bebedouro',
    'Cocho',
    'Cerca',
    'Estrada / Acesso',
  };

  /// O que precisa ser feito do tipo escolhido (vazio = o tipo não tem).
  List<(String, IconData)> get _acoes => _acoesPorTipo[_tipo] ?? const [];
  bool get _comPastos => _tiposComPasto.contains(_tipo);
  final Set<String> _acoesMarcadas = {};
  final Set<int> _pastosMarcados = {};
  List<MapEntry<int, String>> _pastos = [];
  bool _pastosAberto = false;

  /// Tipo "Máquina (manutenção)": qual máquina (uma, obrigatório).
  static const _maquinas = [
    'Trator',
    'Bomba',
    'Implemento',
    'Roçadeira',
    'Moto/Veículo',
    'Outro',
  ];
  String? _maquina;
  bool _maquinaAberta = false;
  bool get _comMaquina => _tipo == 'Máquina (manutenção)';

  /// Pasto + Limpeza: tipo de limpeza (um, obrigatório).
  static const _tiposLimpeza = ['Motofoice', 'Herbicida', 'Trator'];
  String? _tipoLimpeza;
  bool _limpezaAberta = false;
  bool get _comTipoLimpeza =>
      _tipo == 'Pasto' && _acoesMarcadas.contains('Limpeza');

  /// Serviço da lista em edição (índice em [_servicos]); null = novo.
  int? _editando;

  final _rolagem = ScrollController();

  @override
  void initState() {
    super.initState();
    for (final s in widget.servicos ?? const []) {
      _servicos.add(Map<String, dynamic>.from(s));
    }
    _carregarPastos();
    // foi para a descrição: fecha as listas abertas (Tipo, Pastos)
    _descricaoFoco.addListener(() {
      if (_descricaoFoco.hasFocus) _fecharListas();
    });
  }

  /// Pastos da fazenda (do Mapa de Gado guardado no aparelho), na ordem do
  /// Tabuleiro.
  Future<void> _carregarPastos() async {
    final pastos = await MapaGadoDao.instance.pastos(
      widget.bd,
      int.tryParse(widget.fazenda) ?? 0,
      incluirForaTabuleiro: true,
    );
    if (!mounted) return;
    setState(
      () => _pastos = [for (final p in pastos) MapEntry(p.id, p.descricao)],
    );
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    _descricaoFoco.dispose();
    _rolagem.dispose();
    super.dispose();
  }

  /// Fecha as listas abertas (Tipo, Pastos, Qual máquina) ao ir para outro
  /// campo, para não ficarem ocupando a tela.
  void _fecharListas() {
    if (!_tipoAberto && !_pastosAberto && !_maquinaAberta && !_limpezaAberta) {
      return;
    }
    setState(() {
      _tipoAberto = false;
      _pastosAberto = false;
      _maquinaAberta = false;
      _limpezaAberta = false;
    });
  }

  void _limpar() {
    _tipo = null;
    _descricaoController.clear();
    _andamento = null;
    _tipoAberto = false;
    _acoesMarcadas.clear();
    _pastosMarcados.clear();
    _pastosAberto = false;
    _maquina = null;
    _maquinaAberta = false;
    _limpezaAberta = false;
    _tipoLimpeza = null;
  }

  /// "Confirmar Serviço" (ou "Confirmar Edição"): guarda o serviço na lista
  /// (ou grava o editado) e limpa os campos.
  Future<void> _confirmar() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final erro = _tipo == null
        ? 'Selecione o Tipo.'
        : _acoes.isNotEmpty && _acoesMarcadas.isEmpty
        ? 'Marque o que precisa ser feito '
              '(${_acoes.map((a) => a.$1).join(' ou ')}).'
        : _comTipoLimpeza && _tipoLimpeza == null
        ? 'Selecione o Tipo de Limpeza.'
        : _comMaquina && _maquina == null
        ? 'Selecione qual máquina.'
        : _comPastos && _pastosMarcados.isEmpty
        ? 'Selecione o(s) Pasto(s).'
        : _tipo == 'Outro' && _descricaoController.text.trim().isEmpty
        ? 'Descreva o que precisa ser feito.'
        : _andamento == null
        ? 'Marque se o serviço foi feito, está em andamento ou será feito.'
        : null;
    if (erro != null) {
      await AppAlert.erro(context, erro);
      return;
    }
    setState(() {
      final servico = <String, dynamic>{
        'tipo': _tipo,
        // só nos tipos que têm; na ordem das opções
        if (_acoes.isNotEmpty)
          'acoes': [
            for (final o in _acoes)
              if (_acoesMarcadas.contains(o.$1)) o.$1,
          ],
        if (_comTipoLimpeza) 'tipo_limpeza': _tipoLimpeza,
        if (_comMaquina) 'maquina': _maquina,
        if (_comPastos) ...{
          'pastos': [
            for (final p in _pastos)
              if (_pastosMarcados.contains(p.key))
                {'id': p.key, 'nome': p.value},
          ],
        },
        'descricao': _descricaoController.text.trim(),
        'andamento': _andamento,
      };
      if (_editando != null) {
        _servicos[_editando!] = servico;
        _editando = null;
      } else {
        _servicos.add(servico);
      }
      _limpar();
    });
  }

  /// Editar um serviço da lista: os dados dele voltam para os campos.
  void _editar(int n) {
    FocusManager.instance.primaryFocus?.unfocus();
    final s = _servicos[n];
    setState(() {
      _editando = n;
      _limpar();
      _tipo = s['tipo']?.toString();
      _maquina = s['maquina']?.toString();
      _acoesMarcadas.addAll(List<String>.from(s['acoes'] ?? const []));
      for (final p in (s['pastos'] as List? ?? const [])) {
        _pastosMarcados.add((p as Map)['id'] as int);
      }
      _descricaoController.text = '${s['descricao'] ?? ''}';
      _andamento = s['andamento']?.toString();
    });
    _rolagem.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _cancelarEdicao() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _editando = null;
      _limpar();
    });
  }

  /// Excluir um serviço da lista (pergunta antes).
  Future<void> _excluir(int n) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Excluir Serviço',
          style: TextStyle(fontSize: 17, color: _azulTitulo),
        ),
        content: Text('Excluir o Serviço ${n + 1}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('NÃO'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SIM'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      // excluiu o que estava em edição: sai da edição
      if (_editando == n) {
        _editando = null;
        _limpar();
      }
      _servicos.removeAt(n);
      if (_editando != null && _editando! > n) _editando = _editando! - 1;
    });
  }

  /// Select "Tipo" com a lista aberta embaixo do próprio campo: um toque
  /// escolhe (um só) e fecha.
  Widget _selectTipo() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CampoValorTopo(
        rotulo: 'Tipo',
        corRotulo: _corRotulo,
        valor: _tipo ?? '',
        icone: Icon(
          _tipoAberto ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          color: _corRotulo,
        ),
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() {
            _tipoAberto = !_tipoAberto;
            _pastosAberto = false;
            _maquinaAberta = false;
            _limpezaAberta = false;
          });
        },
      ),
      if (_tipoAberto)
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
              for (final t in _tipos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Material(
                    color: t == _tipo
                        ? const Color(0xFFD6E8FA)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() {
                        // trocou o tipo: o que precisa ser feito muda; os
                        // pastos só ficam se o novo tipo também pede
                        if (t != _tipo) {
                          _acoesMarcadas.clear();
                          _maquina = null;
                        }
                        if (!_tiposComPasto.contains(t)) {
                          _pastosMarcados.clear();
                        }
                        _tipo = t;
                        _tipoAberto = false;
                      }),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                t,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: t == _tipo
                                      ? _azulTitulo
                                      : Colors.black87,
                                ),
                              ),
                            ),
                            if (t == _tipo)
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
    ],
  );

  /// Andamento (um só) lado a lado, no mesmo padrão dos botões "Gado Todo /
  /// Parte do Gado / Não Conferi" da Seção 3: ícone em cima, texto embaixo,
  /// azul bem claro e, escolhido, azul mais escuro — sem efeito de toque.
  Widget _opcoesAndamento() {
    const azulIcone = Color(0xFF228cb9);
    return Row(
      children: [
        for (var i = 0; i < _andamentos.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                _fecharListas();
                setState(() => _andamento = _andamentos[i].$1);
              },
              child: Container(
                height: 96,
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                decoration: BoxDecoration(
                  color: _andamento == _andamentos[i].$1
                      ? const Color(0xFFCFE5FA)
                      : const Color(0xFFF9FCFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Icon(_andamentos[i].$2, size: 28, color: azulIcone),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Center(
                        child: Text(
                          _andamentos[i].$1,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: TextStyle(
                            fontFamily: 'FuturaStdMedium',
                            fontSize: 13,
                            color: _corRotulo,
                            shadows: [
                              Shadow(
                                color: _corRotulo,
                                offset: const Offset(0.4, 0),
                              ),
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
      ],
    );
  }

  /// O que precisa ser feito (um ou os dois) lado a lado, no padrão dos botões
  /// do andamento, com o check verde no marcado.
  Widget _opcoesPasto() {
    const azulIcone = Color(0xFF228cb9);
    return Row(
      children: [
        for (var i = 0; i < _acoes.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                _fecharListas();
                final o = _acoes[i].$1;
                setState(() {
                  if (!_acoesMarcadas.remove(o)) {
                    _acoesMarcadas.add(o);
                  }
                });
              },
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _acoesMarcadas.contains(_acoes[i].$1)
                      ? const Color(0xFFCFE5FA)
                      : const Color(0xFFF9FCFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(_acoes[i].$2, size: 22, color: azulIcone),
                    const SizedBox(width: 8),
                    // sempre numa linha: se não couber (ex.: "Manutenção" com o
                    // check), a fonte encolhe um pouco
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _acoes[i].$1,
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: 'FuturaStdMedium',
                            fontSize: 14,
                            color: _corRotulo,
                          ),
                        ),
                      ),
                    ),
                    if (_acoesMarcadas.contains(_acoes[i].$1))
                      Icon(Icons.check, color: Colors.green[600], size: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Select "Pasto(s)" de vários, no mesmo padrão dos outros selects de
  /// vários (Sintomas): lista aberta embaixo do campo, um toque marca ou
  /// desmarca, e os marcados aparecem embaixo do campo em azul claro.
  Widget _selectPastos() {
    final marcados = [
      for (final p in _pastos)
        if (_pastosMarcados.contains(p.key)) p.value,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampoValorTopo(
          rotulo: 'Pasto(s)',
          corRotulo: _corRotulo,
          valor: marcados.isEmpty ? '' : '${marcados.length} selecionado(s)',
          altura: marcados.isEmpty ? 56 : 66,
          icone: Icon(
            _pastosAberto ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            color: _corRotulo,
          ),
          onTap: () async {
            FocusManager.instance.primaryFocus?.unfocus();
            if (_pastos.isEmpty) {
              await AppAlert.erro(
                context,
                'Os pastos desta fazenda ainda não foram baixados neste '
                'aparelho. Abra o Mapa de Gado com internet e tente de novo.',
              );
              return;
            }
            setState(() {
              _pastosAberto = !_pastosAberto;
              _tipoAberto = false;
              _maquinaAberta = false;
              _limpezaAberta = false;
            });
          },
        ),
        if (_pastosAberto)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 5 * 44 + 8),
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
                itemCount: _pastos.length,
                itemBuilder: (context, i) {
                  final p = _pastos[i];
                  final marcado = _pastosMarcados.contains(p.key);
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
                          if (!_pastosMarcados.remove(p.key)) {
                            _pastosMarcados.add(p.key);
                          }
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.value,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: marcado
                                        ? _azulTitulo
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
          ),
        if (marcados.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              marcados.join(', '),
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.blue[300],
                shadows: [
                  Shadow(
                    color: Colors.blue[300]!,
                    offset: const Offset(0.4, 0),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Select "Qual máquina" (uma só) com a lista aberta embaixo do próprio
  /// campo, como o Tipo: um toque escolhe e fecha.
  Widget _selectMaquina() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CampoValorTopo(
        rotulo: 'Qual máquina',
        corRotulo: _corRotulo,
        valor: _maquina ?? '',
        icone: Icon(
          _maquinaAberta ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          color: _corRotulo,
        ),
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() {
            _maquinaAberta = !_maquinaAberta;
            _tipoAberto = false;
            _pastosAberto = false;
          });
        },
      ),
      if (_maquinaAberta)
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
              for (final m in _maquinas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Material(
                    color: m == _maquina
                        ? const Color(0xFFD6E8FA)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => setState(() {
                        _maquina = m;
                        _maquinaAberta = false;
                        _limpezaAberta = false;
                      }),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                m,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: m == _maquina
                                      ? _azulTitulo
                                      : Colors.black87,
                                ),
                              ),
                            ),
                            if (m == _maquina)
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
    ],
  );

  /// Ícone de editar/excluir da lista, no azul do btn-primary.
  Widget _iconeLista(IconData icone, VoidCallback aoTocar) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: aoTocar,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Icon(icone, size: 18, color: _azulBotao),
    ),
  );

  /// Lista dos serviços, com rolagem, do último para o primeiro: "Serviço N",
  /// os tipos, o andamento e os ícones de editar e excluir.
  Widget _listaServicos() {
    final estilo = TextStyle(fontSize: 11, color: _corRotulo);
    final linhas = <TableRow>[];
    for (var n = _servicos.length - 1; n >= 0; n--) {
      final s = _servicos[n];
      final topo = linhas.isNotEmpty ? 8.0 : 2.0;
      linhas.add(
        TableRow(
          // o serviço em edição fica em azul claro
          decoration: n == _editando
              ? const BoxDecoration(color: Color(0xFFD6E8FA))
              : null,
          children: [
            Padding(
              padding: EdgeInsets.only(top: topo, right: 8),
              child: Text('Serviço ${n + 1}', style: estilo),
            ),
            Padding(
              padding: EdgeInsets.only(top: topo, right: 6),
              child: Text('${s['tipo'] ?? ''}', style: estilo),
            ),
            Padding(
              padding: EdgeInsets.only(top: topo, right: 4),
              child: Text('${s['andamento'] ?? ''}', style: estilo),
            ),
            Padding(
              padding: EdgeInsets.only(top: topo - 2),
              child: _iconeLista(Icons.edit_outlined, () => _editar(n)),
            ),
            Padding(
              padding: EdgeInsets.only(top: topo - 2),
              child: _iconeLista(Icons.delete_outline, () => _excluir(n)),
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 12),
      constraints: const BoxConstraints(maxHeight: 150),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            // os tipos ficam com o que sobrar (quebra se precisar)
            columnWidths: const {1: FlexColumnWidth()},
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: linhas,
          ),
        ),
      ),
    );
  }

  /// Botão do modal (Confirmar / Confirmar Edição / Cancelar).
  Widget _botao(
    String texto,
    VoidCallback aoTocar, {
    Color cor = _verde,
    Color corTexto = Colors.white,
  }) => SizedBox(
    height: 46,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: cor,
        foregroundColor: corTexto,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: aoTocar,
      child: Text(texto, style: const TextStyle(fontSize: 15)),
    ),
  );

  bool _tecladoAntes = false;

  @override
  Widget build(BuildContext context) {
    final tecladoAberto = MediaQuery.viewInsetsOf(context).bottom > 0;
    // teclado acabou de abrir: leva o campo em edição para a parte visível
    if (tecladoAberto && !_tecladoAntes) rolarAteCampoEmFoco();
    _tecladoAntes = tecladoAberto;
    return Dialog(
      backgroundColor: Colors.transparent,
      // centralizado, mas sem passar para cima da barra do título "Resumo
      // Diário da Fazenda" quando o conteúdo é alto
      alignment: Alignment.center,
      insetPadding: const EdgeInsets.fromLTRB(16, 72, 16, 24),
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
                    _editando == null
                        ? 'Serviço(s)'
                        : 'Serviço ${_editando! + 1} — editando',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, color: _azulTitulo),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    controller: _rolagem,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      4,
                      12,
                      tecladoAberto ? 160 : 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _selectTipo(),
                        // Máquina (manutenção): qual máquina
                        if (_comMaquina) ...[
                          const SizedBox(height: 12),
                          _selectMaquina(),
                        ],
                        // o que precisa ser feito (Pasto, Bebedouro, Cerca)
                        // e os pastos (ver [_tiposComPasto])
                        if (_acoes.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _opcoesPasto(),
                        ],
                        if (_comPastos) ...[
                          const SizedBox(height: 12),
                          _selectPastos(),
                        ],
                        const SizedBox(height: 12),
                        CampoTextoTopo(
                          rotulo:
                              'Descreva o que precisa ser feito e a urgência',
                          corRotulo: _corRotulo,
                          controller: _descricaoController,
                          focusNode: _descricaoFoco,
                          altura: null,
                          linhas: 3,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: 12),
                        _opcoesAndamento(),
                        const SizedBox(height: 14),
                        if (_editando == null)
                          _botao('Confirmar Serviço', _confirmar)
                        else
                          Row(
                            children: [
                              Expanded(
                                child: _botao(
                                  'Confirmar Edição',
                                  _confirmar,
                                  cor: _azulBotao,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _botao(
                                  'Cancelar',
                                  _cancelarEdicao,
                                  cor: const Color(0xFFE9ECEF),
                                  corTexto: const Color(0xFF333333),
                                ),
                              ),
                            ],
                          ),
                        if (_servicos.isNotEmpty) _listaServicos(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // (x) no canto: fecha; os serviços da lista valem do jeito que
          // estão (só o que está nos campos e não foi confirmado se perde)
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
                onTap: () => Navigator.pop(context, <String, dynamic>{
                  'servicos': _servicos,
                }),
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
